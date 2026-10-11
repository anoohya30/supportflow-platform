# SupportFlow Cloud Infrastructure and GitOps Delivery Platform

> **Engineering assessment / portfolio project** (SkillAnthem Career Accelerator,
> DEVOPS 01). Simulated company, synthetic data. Not a production or commercial
> deployment.

SupportFlow is a small support-ticket API. This repository holds the application
and, as it grows, the platform that builds, deploys, monitors and recovers it:
Terraform (AWS), Docker, k3s, Helm, Argo CD (GitOps), GitHub Actions,
Prometheus and Grafana.

## Status

| Area | Status |
|---|---|
| Ticket API, migrations, tests | ✅ Day 1 |
| Container image, Helm chart, local Kubernetes | ⏳ Day 2 |
| Terraform (AWS) and CI pipeline | ⏳ Day 3 |
| GitOps, monitoring, backups | ⏳ Day 4 |
| Load test, failure exercises, runbooks | ⏳ Day 5 |

## Quick start (local)

Requires Python 3.12+ and Docker.

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt

docker compose up -d               # local PostgreSQL
alembic upgrade head               # create tables
python scripts/seed_tickets.py     # 1,000 synthetic tickets
uvicorn app.main:app --port 8000   # start the API → http://localhost:8000/docs

pytest                             # 19 tests (in another terminal)
python scripts/smoke_test.py       # call every endpoint once
```

## API

| Method | Path | Purpose |
|---|---|---|
| POST | `/tickets` | Create (201 / 422) |
| GET | `/tickets/{id}` | Read (200 / 404) |
| PATCH | `/tickets/{id}` | Update status (200 / 404 / 422) |
| GET | `/tickets?limit=&offset=` | Paginated list (max 100) |
| GET | `/health/live` | Process liveness |
| GET | `/health/ready` | Database readiness (503 when unavailable) |
| GET | `/version` | Release version and Git commit |
| GET | `/metrics` | Prometheus metrics |

## Repository layout

```
app/                 FastAPI service
migrations/          Alembic database migrations
tests/               API contract and operations tests
scripts/             Seed data, smoke test
infra/bootstrap/     Terraform: remote state (Day 3)
infra/platform/      Terraform: VPC, EC2, ECR, S3, IAM (Day 3)
charts/supportflow/  Helm chart (Day 2)
gitops/              Argo CD desired state per environment (Day 4)
.github/workflows/   CI/CD pipelines (Day 3)
load-tests/          k6 load tests (Day 5)
docs/                Guides, decisions, runbooks, evidence
```

## Documentation

- [Day 1 guide](docs/day-1-guide.md)
- [Design decisions](docs/decisions.md)
- [Acceptance evidence index](docs/acceptance-evidence.md)
- [AI assistance disclosure](docs/ai-assistance.md)
