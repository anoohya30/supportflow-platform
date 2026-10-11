"""Shared test setup.

Tests run against a REAL PostgreSQL database (supportflow_test) so they catch
problems a fake database would hide. The schema is built by running the real
Alembic migrations, which also proves the migrations work.
"""

import os

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+psycopg://supportflow:supportflow@localhost:5432/supportflow_test",
)

import pytest  # noqa: E402
from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.db import engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def migrated_database():
    cfg = Config("alembic.ini")
    command.downgrade(cfg, "base")  # start from an empty schema every run
    command.upgrade(cfg, "head")
    yield


@pytest.fixture(autouse=True)
def clean_tickets():
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE tickets RESTART IDENTITY"))
    yield


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def new_ticket(client):
    response = client.post(
        "/tickets",
        json={"subject": "Printer offline", "description": "Synthetic test", "priority": "high"},
    )
    assert response.status_code == 201
    return response.json()
