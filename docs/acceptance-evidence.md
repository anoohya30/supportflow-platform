# Acceptance Evidence Index

One row per requirement in the brief. **Status:** ✅ Done · 🟡 Partial · ❌ Not done.
Evidence files are in `docs/evidence/`; PR numbers refer to this repository.
Lab: AWS eu-west-2, one EC2 host (k3s), environments `staging` and `production-lab`.

**Updated 2026-10-27 after the first review.** Fixes and new evidence:
`day11-review-fixes-drills.md` (drills, HTTPS, alerts, load test) and
`docs/incident-2026-10-27-host-replaced.md` (incident report + clean-room rebuild).
URLs: https://staging.18-135-157-38.sslip.io/docs and https://prod.18-135-157-38.sslip.io/docs

## 1. Product contract

| # | Requirement | Status | Evidence | Result | Limitation |
|---|---|---|---|---|---|
| 1.1 | `POST /tickets` → 201 with ID + timestamp; invalid → 422 | ✅ | `tests/test_tickets.py` (`day1-pytest.txt`); smoke tests on staging and production-lab (`day8-deploy-promote-rollback.md`) | Pass | |
| 1.2 | `GET /tickets/{id}` → ticket or 404 | ✅ | same | Pass | |
| 1.3 | `PATCH /tickets/{id}` updates status | ✅ | same | Pass | |
| 1.4 | `GET /tickets` bounded + paginated | ✅ | same (max 100 per page) | Pass | Offset pagination |
| 1.5 | `/health/live`, `/health/ready` (503 when DB down), `/version` | ✅ | `tests/test_operations.py`; database-kill drill on staging returned one 503 then 200 (`day9-backup-restore-failure-drills.md`) | Pass | |
| 1.6 | `/metrics` with request count, latency histogram, errors | ✅ | `tests/test_operations.py`; scraped by Prometheus, 4/4 targets up (`day9-monitoring-alert-drill.md`) | Pass | |
| 1.7 | Structured JSON logs, no ticket text or credentials | ✅ | `test_logs_are_json_and_exclude_ticket_text` | Pass | |
| 1.8 | Versioned DB migrations | ✅ | Alembic; CI runs upgrade → downgrade → upgrade on every PR | Pass | |
| 1.9 | Previous app version runs after additive migration | 🟡 | Policy: migrations are additive only (runbook 5); rollback demo kept the database untouched and the restored release served traffic (`day8-...`) | Partial | Only one migration exists, so an old-version-on-new-schema test was not run |
| 1.10 | Migration runs once as a Job | ✅ | Helm pre-install/pre-upgrade hook Job `Completed` before API pods start (D-014, `day8-...`) | Pass | |
| 1.11 | Seeded dataset ≥ 1,000 tickets | ✅ | `scripts/seed-env.sh` → `INSERT 0 1000` in each environment | 1,000 per env | Synthetic |

## 2. Acceptance targets

| # | Requirement | Status | Evidence | Result | Limitation |
|---|---|---|---|---|---|
| 2.1 | 2 replicas; 10 min @ 20 rps; p95 < 500 ms; 5xx < 1%; **80 % reads / 20 % creates**; ≥ 1,000 seeded tickets | ✅ | Re-run with the required mix over HTTPS against production-lab (`day11-review-fixes-drills.md` §9, `day11-k6-output.txt`, `day11-k6-summary.json`); earlier run with a different mix: `day10-*` | 12,000 req @ 20.0 rps, **79.9 % reads / 20.1 % creates**, **p95 30.94 ms**, **0.00 % 5xx**, 0 validation errors, 2 replicas | Load generated from a home laptop |
| 2.2 | Rollback to last healthy image < 5 min | ✅ | Drill 04: release that **fails readiness** detected after 97 s, `helm rollback` healthy in 2 s, 10 × 200 for users during the incident, tickets unchanged (`day11-review-fixes-drills.md` §6). Earlier (day 8): non-existent digest | 2 s rollback, no user errors | Manual rollback decision; Helm, not GitOps |
| 2.3 | Restore backup to fresh DB < 30 min; RPO ≤ 15 min | ✅ | Drill 05: encrypted backup into a fresh DB, row counts + 6 selected ticket IDs identical, **API reconnected** and the tickets read through it (`day11-review-fixes-drills.md` §7). Real recovery after host loss: 2,525 + 1,006 tickets (incident report) | **RTO 12 s, RPO 303 s** | Backups only while the host runs; same region |

## 3. Platform, pipeline, observability, recovery

| # | Requirement | Status | Evidence | Limitation |
|---|---|---|---|---|
| 3.1 | Infrastructure as code (Terraform) | ✅ | `infra/bootstrap` (6 resources), `infra/platform` (25 resources) (`day7-platform-up.md`, PR #15) | Single AZ, single host |
| 3.2 | Remote state with locking, encrypted | ✅ | S3 backend, versioned, AES256, public access blocked, `use_lockfile` | Bootstrap state is local by design |
| 3.3 | CI quality gates required before merge | ✅ | 4 required checks (lint/migrations/tests, gitleaks, IaC checks, build + Trivy + SBOM); a failing PR was blocked (`blocked-pr-*.txt`, `branch-protection-test.txt`) | |
| 3.4 | No long-lived cloud credentials in CI | ✅ | GitHub OIDC role, `main` only, immutable subject with repo/owner IDs (D-016, PR #18) | |
| 3.5 | Build once, deploy by digest, promote same artifact | ✅ | `sha256:f8048fab…` running in staging and production-lab (kubectl + `releases.log`, `day8-...`) | |
| 3.6 | Approval gate before production | ❌ | Not completed. Promotion is a manual, logged command run by the operator via Session Manager | Needs the assessor's GitHub identity as required reviewer |
| 3.7 | GitOps (Argo CD) reconciliation | ❌ | Not completed. `gitops/` folders are placeholders; deploys use Helm from the host | No GitOps drift/reconciliation exercise |
| 3.8 | Drift detection | 🟡 | `terraform plan` before every apply; the incident on 27 Oct shows why a scheduled plan is needed (prevention action 6) | No scheduled drift check; no Argo CD drift exercise |
| 3.9 | Dashboards | ✅ | Grafana "SupportFlow" dashboard (`day9-grafana-dashboard.png`) | Not persistent across rebuilds |
| 3.10 | Alerts + notifications | ✅ | Timings match the brief (DB 1 min; 5xx > 5 % over 2 min with a minimum-traffic rule; no ready replicas 1 min); **FIRING and RESOLVED notifications** with timestamps and runbook link at a local webhook collector (drills 02, 03) | Local collector only (allowed by the brief); nobody is paged |
| 3.11 | Failure exercises | ✅ | Scripted drills 01–06 all passed (`day11-review-fixes-drills.md`): NetworkPolicy negative tests, notification, DB outage (ready 503 / live 200, 0 restarts), readiness-failing release + rollback, restore + reconnect, credential rotation. Earlier: pod kill under load (day 9) | Replica-loss test does not prove host loss (single host) |
| 3.16 | Incident report + clean-room reproduction | ✅ | Blameless report on the 27 Oct host replacement, with timeline, causes and prevention actions; rebuild from the repository onto a new host with data recovered from S3 (`docs/incident-2026-10-27-host-replaced.md`) | Reproduced by the same operator, not by an independent assessor |
| 3.12 | Runbooks | ✅ | `docs/runbooks.md` 1–13 (adds 11 DB password rotation, 12 HTTPS certificates, 13 host rebuild / disaster recovery) | |
| 3.13 | Security controls | ✅ | Non-root image, Trivy (fail on fixable critical), gitleaks, checkov (0 failed, documented exceptions), NetworkPolicies (proved by `up=0` before the policy change), IMDSv2, no SSH, only ports 443/80 open, encrypted buckets, **HTTPS with a trusted Let's Encrypt certificate** (HTTP redirects), NetworkPolicy negative tests 6/6 | see `security-exceptions.md` |
| 3.14 | Secrets management and rotation | 🟡 | DB passwords random, stored only in Kubernetes Secrets; **DB password rotated, old credential proven rejected** (drill 06, runbook 11); Grafana admin password rotated (runbook 7) | **AWS Secrets Manager not completed** (D-024) |
| 3.15 | Cost control and cleanup | 🟡 | AWS Free plan credits, budget alarm; teardown runbook 6 | Host kept running during the review window; final teardown after the assessor confirms |

## Scope notes

See `docs/decisions.md` (D-001 to D-020) for every design choice and trade-off,
`docs/security-exceptions.md` for accepted lab risks, and `docs/ai-assistance.md` for the
AI-use disclosure.
