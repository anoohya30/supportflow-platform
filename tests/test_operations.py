"""Tests for health checks, version, metrics and logging."""

import json
import logging

from app.db import get_engine, make_engine
from app.main import app
from app.observability import JsonFormatter


def test_liveness_is_ok(client):
    assert client.get("/health/live").json() == {"status": "alive"}


def test_readiness_is_ok_when_database_is_up(client):
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["database"] == "reachable"


def test_readiness_returns_503_but_liveness_stays_ok_when_database_is_down(client):
    # Point the readiness check at a port where no database is listening.
    broken = make_engine("postgresql+psycopg://nobody:nothing@127.0.0.1:1/none")
    app.dependency_overrides[get_engine] = lambda: broken
    try:
        assert client.get("/health/ready").status_code == 503
        assert client.get("/health/live").status_code == 200  # no restart loop
    finally:
        app.dependency_overrides.clear()


def test_version_reports_release_and_commit(client):
    body = client.get("/version").json()
    assert set(body) == {"version", "commit"}


def test_metrics_exposes_requests_latency_and_errors(client):
    client.get("/tickets/999999")  # generate some traffic first
    text = client.get("/metrics").text

    assert "http_requests_total" in text
    assert "http_request_duration_seconds_bucket" in text
    assert "http_request_errors_total" in text
    # Uses the route template, not the real ID, to keep metrics small.
    assert 'route="/tickets/{ticket_id}"' in text


class ListHandler(logging.Handler):
    """Collects formatted log lines in a list so the test can inspect them."""

    def __init__(self):
        super().__init__()
        self.setFormatter(JsonFormatter())
        self.lines = []

    def emit(self, record):
        self.lines.append(self.format(record))


def test_logs_are_json_and_exclude_ticket_text(client):
    logger = logging.getLogger("supportflow")
    handler = ListHandler()
    logger.addHandler(handler)
    try:
        secret_text = "VERY-PRIVATE-DESCRIPTION"
        client.post(
            "/tickets",
            json={"subject": "Log test", "description": secret_text, "priority": "low"},
            headers={"X-Request-ID": "test-123"},
        )
    finally:
        logger.removeHandler(handler)

    line = handler.lines[-1]
    entry = json.loads(line)
    assert entry["request_id"] == "test-123"
    assert entry["route"] == "/tickets"
    assert entry["status"] == 201
    for field in ("timestamp", "level", "release"):
        assert field in entry
    assert secret_text not in line
