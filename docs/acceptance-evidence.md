# Acceptance Evidence Index

One row per requirement in the brief. **Status:** ✅ Done · 🟡 Partial · ❌ Not done ·
⏳ Not started. Every ✅ needs runnable evidence (command output, workflow run link,
dashboard export or recording timestamp), not just a screenshot.

## 1. Product contract

| # | Requirement | Status | Evidence (command / file / link) | Result | Limitation |
|---|---|---|---|---|---|
| 1.1 | `POST /tickets` → 201 with ID + timestamp; invalid → 422 | ✅ | `pytest tests/test_tickets.py` → `docs/evidence/day1-pytest.txt` | Pass | |
| 1.2 | `GET /tickets/{id}` → ticket or 404 | ✅ | same | Pass | |
| 1.3 | `PATCH /tickets/{id}` updates status | ✅ | same | Pass | |
| 1.4 | `GET /tickets` bounded + paginated | ✅ | same (max 100/page) | Pass | Offset pagination |
| 1.5 | `/health/live`, `/health/ready` (503 when DB down), `/version` | ✅ | `tests/test_operations.py`; manual DB-stop check (guide F9) | Pass | Local only so far |
| 1.6 | `/metrics` with request count, latency histogram, errors | ✅ | `tests/test_operations.py` | Pass | |
| 1.7 | Structured JSON logs, no ticket text or credentials | ✅ | `test_logs_are_json_and_exclude_ticket_text` | Pass | |
| 1.8 | Versioned DB migrations | ✅ | `alembic upgrade head`; tests build schema via migrations | Pass | |
| 1.9 | Previous app version runs after additive migration | ⏳ | Day 2/4 | | |
| 1.10 | Migration runs once as a Job | ⏳ | Day 2 | | |
| 1.11 | Seeded dataset ≥ 1,000 tickets | ✅ | `python scripts/seed_tickets.py` | 1,000 inserted | |

## 2. Acceptance targets

| # | Requirement | Status | Evidence | Result | Limitation |
|---|---|---|---|---|---|
| 2.1 | 2 replicas; 10 min @ 20 rps; p95 < 500 ms; 5xx < 1% | ⏳ | Day 5 | | |
| 2.2 | Rollback to last healthy image < 5 min | ⏳ | Day 5 | | |
| 2.3 | Restore backup to fresh DB < 30 min; RPO ≤ 15 min | ⏳ | Day 5 | | |

## 3. Platform, pipeline, observability, recovery

*(Add rows on Days 2–5: Terraform, OIDC, CI gates, build-once/promote, approval gate,
GitOps, rollback, drift, dashboards, alerts, failure exercises, runbooks, security
checks, cleanup.)*

## Scope notes

See `docs/decisions.md` D-008 and the assessor's written reply in
`docs/evidence/`.
