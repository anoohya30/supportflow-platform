# AI Assistance and External Code Disclosure

The assessment brief permits documentation and AI tools, but requires disclosure.
I own and can explain everything submitted.

## AI assistance

| Date | Tool | What it helped with | What I did |
|---|---|---|---|
| 2026-10-09 | Claude (Anthropic) | Explaining the brief; generating the starter FastAPI service, Alembic migration, tests, seed and smoke-test scripts, and the Day 1 guide | Read and ran all code, verified the tests pass locally, adjusted design decisions |
| 2026-10-11 to 10-12 | Claude (Anthropic) | Dockerfile, CI workflow (lint, migrations, tests, gitleaks, Trivy, SBOM) | Ran the container locally as non-root, ran CI, tested branch protection by letting a failing PR be blocked |
| 2026-10-12 to 10-16 | Claude (Anthropic) | Terraform (bootstrap + platform), Helm chart, Postgres manifest, deploy/seed scripts, checkov config, runbooks | Reviewed every plan before applying, switched to a Free-plan instance type (D-015), diagnosed and fixed the OIDC trust failure caused by GitHub's immutable subject claims (D-016) |
| 2026-10-17 | Claude (Anthropic) | Step-by-step guidance for deploy, promotion and rollback | Ran every command myself on the host through Session Manager, recorded the results in docs/evidence |
| 2026-10-19 | Claude (Anthropic) | Monitoring values, alert rules, Grafana dashboard, backup/restore scripts | Installed and verified monitoring, ran the alert drill, backup/restore drill and failure drills, rotated the exposed Grafana password |
| 2026-10-20 | Claude (Anthropic) | k6 load test script, documentation updates | Ran the load test against staging and recorded the results |

**How I used it:** AI produced first drafts and explanations; I ran, checked and
corrected everything against the real system. Where the AI was wrong or the platform
behaved differently (for example the Free-plan instance type, the OIDC subject format,
a pasted command splitting into two lines), the fix and the evidence are recorded in
`docs/decisions.md` and `docs/evidence/`. No secrets, credentials or account IDs were
shared with the AI tool on purpose; one accidental exposure (Grafana password) was
rotated.

## External code and libraries

No code was copied from external repositories. The project uses these open-source
libraries (installed from PyPI, versions pinned in `requirements*.txt`):

| Library | Purpose | Licence |
|---|---|---|
| FastAPI | Web framework | MIT |
| Uvicorn | ASGI server | BSD-3-Clause |
| SQLAlchemy | Database toolkit | MIT |
| psycopg | PostgreSQL driver | LGPL-3.0 |
| Alembic | Database migrations | MIT |
| prometheus-client | Metrics | Apache-2.0 |
| Pydantic | Validation | MIT |
| pytest, httpx, ruff | Testing and linting (dev only) | MIT / BSD-3-Clause / MIT |

Platform tools (not copied into the repo; used as published): Terraform and the AWS
provider (BUSL-1.1 / MPL-2.0), k3s (Apache-2.0), Helm (Apache-2.0),
kube-prometheus-stack chart (Apache-2.0), PostgreSQL image (PostgreSQL licence),
k6 (AGPL-3.0, run as a container only), gitleaks (MIT), Trivy (Apache-2.0),
checkov (Apache-2.0), kubeconform (Apache-2.0).
