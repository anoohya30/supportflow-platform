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

---

## D-012: Admin access through AWS Session Manager, not SSH
*Status: Accepted · 2026-10-12*

**Decision:** The lab host has no SSH, Kubernetes API or database port open.
Operators connect with `aws ssm start-session`. Only port 80 (the app) is public.

**Why:** No exposed login port, no SSH keys, works when the operator's IP changes,
and every session is authenticated by IAM. This is the "authenticated tunnel" in the brief.

**Trade-off:** Needs the Session Manager plugin locally and the SSM agent on the host.

---

## D-013: Same image digest promoted from staging to production-lab
*Status: Accepted · 2026-10-12*

**Decision:** CI builds the image once, scans it, and (on `main` only) pushes it to an
immutable-tag ECR repo using GitHub OIDC. Deployments always use `repository@sha256:digest`;
the deploy script refuses tags. Production-lab gets the exact digest that passed staging.

**Why:** "Build once, promote" means what was tested is exactly what runs.

**Trade-off:** Promotion is a manual script run through Session Manager, not GitOps.
Argo CD reconciliation and a reviewer-enforced promotion gate are not completed.

---

## D-014: Migrations as a Helm pre-install/pre-upgrade Job
*Status: Accepted · 2026-10-12*

**Decision:** `alembic upgrade head` runs once in a Helm hook Job before the API rolls out,
never at replica startup. The rolling update keeps both old pods until a new one is Ready
(`maxUnavailable: 0`).

**Why:** Avoids two replicas racing to migrate, and a failed migration stops the release
before any API pod changes.

**Trade-off:** A failed hook blocks the release until fixed (intended).

---

## D-015: m7i-flex.large instead of t3.large (AWS Free plan)
*Status: Accepted · 2026-10-14*

**Decision:** The lab host uses `m7i-flex.large` (2 vCPU, 8 GB) instead of `t3.large`.

**Why:** The lab AWS account is on the AWS Free plan (credits, 6 months). `t3.large` is not
Free-plan eligible; `m7i-flex.large` is, and has the same 8 GB memory needed for k3s plus
staging and production-lab. Usage is paid from Free plan credits, not a card.

**Trade-off:** Free plan credits are limited, so the platform is torn down at the end of the
review window (runbook 6). A real service would size from load-test results instead.

---

## D-016: Trust GitHub's immutable OIDC subject
*Status: Accepted · 2026-10-16*

**Decision:** The ECR push role trusts the OIDC subject
`repo:anoohya30@262563569/supportflow-platform@1413030078:ref:refs/heads/main`
(owner and repository numeric IDs), not the legacy name-only subject.

**Why:** The first push to `main` failed with `Not authorized to perform
sts:AssumeRoleWithWebIdentity`. Repositories created after 15 July 2026 receive GitHub's
immutable subject format; this repository was created on 2026-10-10. Numeric IDs cannot
be reused, so a deleted-and-recreated repository with the same name cannot assume the role.

**Trade-off:** If the repository is transferred to another owner, the IDs in
`variables.tf` must be updated.

---

## D-017: kube-prometheus-stack, reached only through Session Manager
*Status: Accepted · 2026-10-19*

**Decision:** Monitoring uses the kube-prometheus-stack Helm chart (pinned version) in a
`monitoring` namespace: Prometheus scrapes the API's `/metrics` in both environments,
Alertmanager evaluates five SupportFlow alert rules, Grafana shows a SupportFlow dashboard.
The UIs use NodePorts that the security group does not open; they are reached only through
Session Manager port forwarding.

**Why:** One chart gives metrics, alerts, dashboards and Kubernetes state metrics with little
custom code. No new public endpoint and no extra login surface on the internet.

**Trade-off:** Uses about 1 GB of the host's memory. No alert notification channel
(email/Slack) is configured. Data is lost if the host is rebuilt (3-day retention, no
persistent volume).

---

## D-018: Logical backups to S3 with a non-destructive restore drill
*Status: Accepted · 2026-10-19*

**Decision:** `scripts/backup-db.sh` streams `pg_dump --format=custom` straight to the
encrypted, versioned backups bucket using the host's IAM role. `scripts/restore-db.sh`
restores the newest backup into a scratch database and compares counts with the live
database. A systemd timer can run backups daily.

**Why:** A backup only counts once a restore has been proven. Restoring into a scratch
database proves the backup without risking live data.

**Trade-off:** Point-in-time recovery is not available (only whole dumps). Backups live in
the same region as the host.

---

## D-019: Backups every 15 minutes (RPO 15 min)
*Status: Accepted · 2026-10-20*

**Decision:** The systemd backup timer runs `scripts/backup-db.sh` for both environments
every 15 minutes (`OnCalendar=*:0/15`, `Persistent=true`) instead of once a day.

**Why:** Acceptance target 2.3 requires a recovery point objective of 15 minutes or less.
Each dump is about 10 KB, so frequent backups cost almost nothing; old object versions
expire through the bucket lifecycle rule.

**Trade-off:** No backups are taken while the lab host is stopped (there is also no data
change then); the first backup after a start runs immediately because of `Persistent=true`.
For a real service, continuous WAL archiving (point-in-time recovery) would replace dumps.

---

## D-020: Load test with k6 from the laptop, by Docker
*Status: Accepted · 2026-10-20*

**Decision:** `load-tests/k6-tickets.js` uses a constant-arrival-rate scenario (20 req/s
for 10 min) with thresholds for p95 latency and 5xx rate, run with the pinned
`grafana/k6:1.8.1` container from the laptop against staging over the internet.

**Why:** Running the load generator outside the cluster measures the real user path
(internet -> Traefik -> API -> PostgreSQL) and does not steal CPU from the host under test.
Docker avoids installing k6.

**Trade-off:** Results include the laptop's home network latency; a dedicated load
generator in the same region would give cleaner numbers.
