# Design Decisions

Each decision records **what** was chosen, **why**, and the **trade-off** accepted.
New decisions are added at the bottom. Old ones are never deleted; if a decision
changes, mark it *Superseded by D-00X*.

Format: *Status: Accepted / Proposed / Superseded* · *Date*

---

## D-001: Build a minimal FastAPI + PostgreSQL service ourselves
*Status: Accepted · 2026-10-09*

**Decision:** Write a small FastAPI service from scratch rather than adapt a starter.

**Why:** The contract is small (8 endpoints). Writing it means there is no third-party
licence to track and I understand every line, which the assessor will test.

**Trade-off:** No frontend or authentication. Both are explicitly out of scope in the
brief.

---

## D-002: Liveness does not check the database; readiness does
*Status: Accepted · 2026-10-09*

**Decision:** `/health/live` only confirms the process responds. `/health/ready` runs
`SELECT 1` with a 2-second connect and statement timeout and returns 503 on failure.

**Why:** If the database is down, restarting API pods does not help and causes
restart loops. Readiness removes the pod from traffic instead. The timeout keeps
the check bounded so probes don't pile up.

**Trade-off:** A pod with a broken database connection stays running (not
restarted). This is intended.

---

## D-003: Alembic for versioned, additive migrations, run once as a Job
*Status: Accepted · 2026-10-09*

**Decision:** Schema changes are numbered Alembic migrations. In Kubernetes they run
once in a dedicated migration Job before the API rollout, never at replica startup.
Changes used in the assessed release are **additive** (new nullable columns/tables
only).

**Why:** Running migrations at startup with two replicas causes races. Additive
changes mean the previous app version still works after the migration, so an
application rollback doesn't require a schema rollback.

**Trade-off:** Removing or renaming columns needs a multi-step "expand, then contract"
process over several releases.

---

## D-004: Integer ticket IDs with offset pagination (max 100 per page)
*Status: Accepted · 2026-10-09*

**Decision:** `BIGINT` auto-increment IDs. `GET /tickets` uses `limit` (1–100,
default 20) and `offset`.

**Why:** Simple to understand and test. The brief requires a "bounded" list, and the
100-item cap enforces it.

**Trade-off:** Offset pagination gets slower on very large tables, and sequential IDs
reveal ticket volume. A real service could use keyset pagination and UUIDs.

---

## D-005: Configuration through environment variables
*Status: Accepted · 2026-10-09*

**Decision:** All settings (`DATABASE_URL`, `APP_VERSION`, `GIT_COMMIT`, timeouts)
come from environment variables with safe local defaults.

**Why:** One image is built once and promoted unchanged from staging to
production-lab (build once, promote). Only configuration differs. No secrets in code
or images.

**Trade-off:** Local defaults include a throwaway local password
(`supportflow`). It's only valid for the laptop Docker database and is never used in
AWS.

---

## D-006: Observability built into the app from day one
*Status: Accepted · 2026-10-09*

**Decision:** Prometheus metrics (request counter, latency histogram with buckets
5 ms – 5 s, 5xx counter) labelled by **route template**. One structured JSON log line
per request with timestamp, level, request ID, route, status, duration, release and
commit. Ticket text and credentials are never logged.

**Why:** Required by the brief. Route templates keep metric cardinality low. The
histogram buckets bracket the 500 ms p95 target.

**Trade-off:** In-process metrics reset when a pod restarts. Prometheus `rate()`
handles counter resets.

---

## D-007: Single EC2 host running k3s (lab cost compromise)
*Status: Accepted · 2026-10-09*

**Decision:** One EC2 instance runs k3s. `staging` and `production-lab` are separate
namespaces with separate databases, credentials and config. PostgreSQL runs in the
cluster on a persistent volume.

**Why:** Mandated by the brief to control cost.

**Trade-off / what a real service would need:** Namespaces are logical separation
only. A host failure takes down both environments and the database. For production:
separate clusters per environment (e.g. EKS), managed PostgreSQL (e.g. RDS Multi-AZ),
and capacity across multiple availability zones.

---

## D-008: Scope for the 5-day delivery
*Status: Proposed · 2026-10-09 (awaiting assessor confirmation)*

**Decision:** Deliver the core path first: app → image → CI gates → staging →
approved promotion → monitoring → rollback → backup/restore. Items that may be
reported as **not completed**: network-policy negative tests, credential rotation,
drift demonstrations, HTTPS with a custom domain, all extensions.

**Why:** The brief estimates 60–80 hours over 14 days. It requires incomplete items
to be reported explicitly rather than silently omitted.

---

## D-009: Kubernetes runs only on the AWS lab host, not locally
*Status: Accepted · 2026-10-11*

**Decision:** The laptop (3.6 GB RAM) is used for code, tests and building images only.
All Kubernetes work (k3s, Helm, Argo CD, Prometheus, Grafana) runs on the AWS EC2 host.

**Why:** A local cluster plus monitoring needs more memory than the laptop has.
The brief requires k3s on EC2 anyway, so the assessed environment is unchanged.

**Trade-off:** Kubernetes mistakes are found on AWS instead of locally. Reduced by
`helm lint` / `helm template` checks and by deploying to staging before production-lab.

---

## D-010: Two-stage, non-root container image
*Status: Accepted · 2026-10-11*

**Decision:** The Dockerfile uses a builder stage to install libraries and a clean
final stage with only the libraries and app code. The app runs as user 10001 (not root).

**Why:** Smaller image with no build tools, and less damage possible if the app is
compromised. Proven locally: `docker exec ... id` shows `uid=10001(app)`.

**Trade-off:** The base image is a version tag (`python:3.13-slim`), not a fixed digest,
so it can change between builds. The CI vulnerability scan checks every build.

---

## D-011: CI with pinned actions and security gates
*Status: Accepted · 2026-10-11*

**Decision:** GitHub Actions runs lint, migration check, tests, a gitleaks secret scan
and a Trivy image scan on every pull request. Third-party actions are pinned to exact
commit SHAs. The workflow has read-only permissions and uses no secrets.

**Why:** Required by the brief. Pinning by SHA stops a changed action from silently
running different code.

**Trade-off:** The image is built but not pushed yet; pushing to ECR via GitHub OIDC is
added when the AWS infrastructure exists (Day 4).
