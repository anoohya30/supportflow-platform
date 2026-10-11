"""API contract tests for the /tickets endpoints."""

import pytest

VALID = {"subject": "Cannot log in", "description": "Synthetic ticket", "priority": "normal"}


# ------------------------------------------------------------ POST create ---
def test_create_ticket_returns_201_with_id_and_timestamp(client):
    response = client.post("/tickets", json=VALID)

    assert response.status_code == 201
    body = response.json()
    assert isinstance(body["id"], int)
    assert body["created_at"]
    assert body["status"] == "open"  # default status
    assert body["priority"] == "normal"


@pytest.mark.parametrize(
    "payload",
    [
        {**VALID, "priority": "urgent"},  # not an allowed priority
        {"subject": "No description", "priority": "low"},  # missing field
        {**VALID, "subject": ""},  # empty subject
        {**VALID, "subject": "x" * 201},  # subject too long
        {**VALID, "status": "closed"},  # unknown extra field
    ],
)
def test_create_ticket_rejects_invalid_input_with_422(client, payload):
    assert client.post("/tickets", json=payload).status_code == 422


# --------------------------------------------------------------- GET one ---
def test_get_ticket_returns_stored_ticket(client, new_ticket):
    response = client.get(f"/tickets/{new_ticket['id']}")

    assert response.status_code == 200
    assert response.json() == new_ticket


def test_get_missing_ticket_returns_404(client):
    assert client.get("/tickets/999999").status_code == 404


# ----------------------------------------------------------- PATCH status ---
def test_patch_updates_status(client, new_ticket):
    response = client.patch(f"/tickets/{new_ticket['id']}", json={"status": "in_progress"})

    assert response.status_code == 200
    assert response.json()["status"] == "in_progress"
    assert client.get(f"/tickets/{new_ticket['id']}").json()["status"] == "in_progress"


def test_patch_rejects_invalid_status_with_422(client, new_ticket):
    response = client.patch(f"/tickets/{new_ticket['id']}", json={"status": "done"})
    assert response.status_code == 422


def test_patch_missing_ticket_returns_404(client):
    assert client.patch("/tickets/999999", json={"status": "closed"}).status_code == 404


# -------------------------------------------------------------- GET list ---
def test_list_is_paginated(client):
    for i in range(25):
        client.post("/tickets", json={**VALID, "subject": f"Ticket {i}"})

    page1 = client.get("/tickets?limit=10&offset=0").json()
    page3 = client.get("/tickets?limit=10&offset=20").json()

    assert page1["total"] == 25
    assert len(page1["items"]) == 10
    assert len(page3["items"]) == 5
    assert page1["items"][0]["subject"] == "Ticket 0"


def test_list_has_a_maximum_page_size(client):
    assert client.get("/tickets?limit=101").status_code == 422
    assert client.get("/tickets?limit=100").status_code == 200
