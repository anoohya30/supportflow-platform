"""Structured JSON logging and Prometheus metrics."""

import json
import logging
import sys
from datetime import UTC, datetime

from prometheus_client import Counter, Histogram

from app import config

# ---------------------------------------------------------------- metrics ---
# Route labels use the route *template* (e.g. /tickets/{ticket_id}), never the
# real URL, so the number of metric series stays small.

REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests handled",
    ["method", "route", "status"],
)

LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "route"],
    # Buckets chosen around the 500 ms p95 target in the brief.
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

ERRORS = Counter(
    "http_request_errors_total",
    "HTTP requests that ended in a 5xx server error",
    ["method", "route"],
)


# ---------------------------------------------------------------- logging ---
class JsonFormatter(logging.Formatter):
    """One JSON object per log line. Never includes ticket text or secrets."""

    FIELDS = ("request_id", "method", "route", "status", "duration_ms")

    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "release": config.APP_VERSION,
            "commit": config.GIT_COMMIT,
        }
        for field in self.FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                entry[field] = value
        if record.exc_info:
            # Exception type only: a full message could contain request data.
            entry["error"] = record.exc_info[0].__name__
        return json.dumps(entry)


def setup_logging() -> logging.Logger:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger("supportflow")
    logger.handlers = [handler]
    logger.setLevel(config.LOG_LEVEL)
    logger.propagate = False
    # Silence uvicorn's plain-text access log; our middleware logs every request.
    logging.getLogger("uvicorn.access").disabled = True
    return logger
