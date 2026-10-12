"""SupportFlow API: a minimal support-ticket service.

Endpoints (from the assessment's product contract):
  POST  /tickets            create a ticket                -> 201 / 422
  GET   /tickets/{id}       read one ticket                -> 200 / 404
  PATCH /tickets/{id}       change status                  -> 200 / 404 / 422
  GET   /tickets            paginated list (limit/offset)  -> 200
  GET   /health/live        is the process alive?          -> 200
  GET   /health/ready       can we reach the database?     -> 200 / 503
  GET   /version            release version and Git commit
  GET   /metrics            Prometheus metrics
"""

import time
import uuid
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy import func, select
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from app import config
from app.db import database_is_reachable, get_engine, get_session
from app.models import Ticket
from app.observability import ERRORS, LATENCY, REQUESTS, setup_logging
from app.schemas import TicketCreate, TicketOut, TicketPage, TicketStatusUpdate

logger = setup_logging()

app = FastAPI(title="SupportFlow", version=config.APP_VERSION)

SessionDep = Annotated[Session, Depends(get_session)]
MAX_PAGE_SIZE = 100


# ------------------------------------------------------------- middleware ---
@app.middleware("http")
async def observe_requests(request: Request, call_next):
    """Give every request an ID, then record metrics and one JSON log line."""
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    start = time.perf_counter()
    try:
        response = await call_next(request)
        status_code = response.status_code
    except Exception:
        status_code = 500
        response = JSONResponse({"detail": "Internal server error"}, status_code=500)
        logger.exception("unhandled error", extra={"request_id": request_id})

    duration = time.perf_counter() - start
    route = request.scope.get("route")
    route_template = route.path if route else "unmatched"

    REQUESTS.labels(request.method, route_template, str(status_code)).inc()
    LATENCY.labels(request.method, route_template).observe(duration)
    if status_code >= 500:
        ERRORS.labels(request.method, route_template).inc()

    response.headers["X-Request-ID"] = request_id
    if route_template != "/metrics":  # keep Prometheus scrapes out of the logs
        logger.info(
            "request",
            extra={
                "request_id": request_id,
                "method": request.method,
                "route": route_template,
                "status": status_code,
                "duration_ms": round(duration * 1000, 2),
            },
        )
    return response


# ---------------------------------------------------------------- tickets ---
def _get_ticket_or_404(session: Session, ticket_id: int) -> Ticket:
    ticket = session.get(Ticket, ticket_id)
    if ticket is None:
        raise HTTPException(status_code=404, detail="Ticket not found")
    return ticket


@app.post("/tickets", response_model=TicketOut, status_code=status.HTTP_201_CREATED)
def create_ticket(payload: TicketCreate, session: SessionDep):
    ticket = Ticket(**payload.model_dump())
    session.add(ticket)
    session.commit()
    session.refresh(ticket)
    return ticket


@app.get("/tickets/{ticket_id}", response_model=TicketOut)
def get_ticket(ticket_id: int, session: SessionDep):
    return _get_ticket_or_404(session, ticket_id)


@app.patch("/tickets/{ticket_id}", response_model=TicketOut)
def update_ticket_status(ticket_id: int, payload: TicketStatusUpdate, session: SessionDep):
    ticket = _get_ticket_or_404(session, ticket_id)
    ticket.status = payload.status
    ticket.updated_at = func.now()
    session.commit()
    session.refresh(ticket)
    return ticket


@app.get("/tickets", response_model=TicketPage)
def list_tickets(
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_SIZE)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    total = session.scalar(select(func.count()).select_from(Ticket))
    rows = session.scalars(select(Ticket).order_by(Ticket.id).limit(limit).offset(offset))
    return TicketPage(items=list(rows), limit=limit, offset=offset, total=total)


# ------------------------------------------------------- health & version ---
@app.get("/health/live")
def live():
    """Liveness: the process is running. Deliberately does NOT check the
    database, so a database outage does not make Kubernetes restart the API."""
    return {"status": "alive"}


@app.get("/health/ready")
def ready(engine: Annotated[Engine, Depends(get_engine)]):
    """Readiness: can this replica serve traffic? Fails with 503 when the
    database is unreachable, so Kubernetes stops sending requests here."""
    if database_is_reachable(engine):
        return {"status": "ready", "database": "reachable"}
    return JSONResponse(
        {"status": "not_ready", "database": "unreachable"},
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
    )


@app.get("/version")
def version():
    return {"version": config.APP_VERSION, "commit": config.GIT_COMMIT}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
import json  # DELIBERATE ERROR: unused import to prove CI blocks merging
