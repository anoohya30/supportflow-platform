# SupportFlow Cloud Infrastructure and GitOps Delivery Platform

> **Engineering assessment / portfolio project** (SkillAnthem Career Accelerator,
> DEVOPS 01). Simulated company, synthetic data. Not a production or commercial
> deployment.

SupportFlow is a small support-ticket API. This repository holds the application
and the platform that builds, deploys, monitors and recovers it: Terraform (AWS),
Docker, GitHub Actions (OIDC to AWS), Amazon ECR, k3s on EC2, Helm, Prometheus,
Grafana, Alertmanager, S3 backups and k6.

## Status

| Area | Status |
|---|---|
| Ticket API, migrations, tests (19), smoke test | ✅ |
| Container image (non-root), CI with 4 required checks, secret + vulnerability scan, SBOM | ✅ |
| Terraform: remote state + platform (VPC, EC2 k3s host, ECR, IAM/OIDC, S3 backups) | ✅ |
| Image built once, pushed by digest via GitHub OIDC (no stored AWS keys) | ✅ |
| Helm deploy to staging, promotion of the same digest to production-lab, rollback | ✅ |
| Prometheus, Grafana dashboard, 5 alert rules, alert drill | ✅ |
| Backups to S3 every 15 min, restore drill, failure drills | ✅ |
| k6 load test (10 min @ 20 req/s) | see `docs/evidence/` |
| Argo CD (GitOps reconciliation), reviewer-enforced promotion gate, alert notifications | ❌ not completed (see acceptance evidence) |

**Architecture (lab):**

```
GitHub (PR -> 4 required checks) --merge--> main --CI--> build once, scan, SBOM
        |                                                   | OIDC (main only)
        v                                                   v
   reviewer / me                                     Amazon ECR (image@sha256)
                                                            |
 laptop --Session Manager (no SSH)--> EC2 m7i-flex.large (k3s, eu-west-2)
                                       |- staging:        2 x API + PostgreSQL
                                       |- production-lab: 2 x API + PostgreSQL (same digest)
                                       |- monitoring:     Prometheus, Alertmanager, Grafana
                                       '- backup timer -> S3 (encrypted, versioned)
 users --HTTP :80 (only open port)--> Traefik -> staging.<ip>.sslip.io / prod.<ip>.sslip.io
```

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
scripts/             Seed, smoke test, deploy, backup/restore, monitoring install
infra/bootstrap/     Terraform: remote state bucket
infra/platform/      Terraform: VPC, EC2 k3s host, ECR, S3 backups, IAM/OIDC
charts/supportflow/  Helm chart (API, migration Job, NetworkPolicy, ingress)
k8s/                 PostgreSQL StatefulSet per environment
monitoring/          kube-prometheus-stack values, alert rules, Grafana dashboard
load-tests/          k6 load test
.github/workflows/   CI pipeline
docs/                Decisions, runbooks, evidence, security exceptions
```

## Documentation

- [Acceptance evidence index](docs/acceptance-evidence.md) (start here)
- [Runbooks](docs/runbooks.md): provision, connect, deploy, promote, rollback, teardown, monitoring, backup/restore, failure drills
- [Design decisions](docs/decisions.md) (D-001 to D-020)
- [Security exceptions](docs/security-exceptions.md)
- [Evidence files](docs/evidence/)
- [AI assistance disclosure](docs/ai-assistance.md)
- [Day 1 guide](docs/day-1-guide.md)
