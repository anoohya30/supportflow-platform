# Acceptance Evidence Index

One row per requirement in the brief. **Status:** ✅ Done · 🟡 Partial · ❌ Not done.
Evidence files are in `docs/evidence/`; PR numbers refer to this repository.
Lab: AWS eu-west-2, one EC2 host (k3s), environments `staging` and `production-lab`.

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
| 2.1 | 2 replicas; 10 min @ 20 rps; p95 < 500 ms; 5xx < 1% | ✅ | k6 load test against staging (`day10-load-test-rpo.md`, `day10-k6-output.txt`, `day10-k6-summary.json`) | 12,001 req @ 20.0 rps, **p95 28.21 ms**, **0.00% 5xx**, 2 replicas | Load generated from a home laptop |
| 2.2 | Rollback to last healthy image < 5 min | ✅ | Bad release (non-existent digest) failed at about 13:38 UTC; `helm rollback` → revision 3 deployed 13:40:27 UTC; 60 × 200 on an uptime loop (`day8-...`) | < 3 min, no downtime | Manual rollback (no automatic trigger) |
| 2.3 | Restore backup to fresh DB < 30 min; RPO ≤ 15 min | ✅ | Restore drill into a fresh database, counts matched (`day9-backup-restore-failure-drills.md`); backup timer every 15 min, runs succeeded (`day10-load-test-rpo.md`) | Restore about 5 s; RPO 15 min | Backups only while the host runs; same region |

## 3. Platform, pipeline, observability, recovery

| # | Requirement | Status | Evidence | Limitation |
|---|---|---|---|---|
| 3.1 | Infrastructure as code (Terraform) | ✅ | `infra/bootstrap` (6 resources), `infra/platform` (25 resources) (`day7-platform-up.md`, PR #15) | Single AZ, single host |
| 3.2 | Remote state with locking, encrypted | ✅ | S3 backend, versioned, AES256, public access blocked, `use_lockfile` | Bootstrap state is local by design |
| 3.3 | CI quality gates required before merge | ✅ | 4 required checks (lint/migrations/tests, gitleaks, IaC checks, build + Trivy + SBOM); a failing PR was blocked (`blocked-pr-*.txt`, `branch-protection-test.txt`) | |
| 3.4 | No long-lived cloud credentials in CI | ✅ | GitHub OIDC role, `main` only, immutable subject with repo/owner IDs (D-016, PR #18) | |
| 3.5 | Build once, deploy by digest, promote same artifact | ✅ | `sha256:f8048fab…` running in staging and production-lab (kubectl + `releases.log`, `day8-...`) | |
| 3.6 | Approval gate before production | ❌ | Not completed. Promotion is a manual, logged command run by the operator via Session Manager | Solo lab; no second reviewer |
| 3.7 | GitOps (Argo CD) reconciliation | ❌ | Not completed. `gitops/` folders are placeholders; deploys use Helm from the host | |
| 3.8 | Drift detection | 🟡 | `terraform plan` before every apply showed only expected changes | No scheduled drift check |
| 3.9 | Dashboards | ✅ | Grafana "SupportFlow" dashboard (`day9-grafana-dashboard.png`) | Not persistent across rebuilds |
| 3.10 | Alerts | 🟡 | 5 alert rules; alert drill: firing 2 min after outage, received by Alertmanager, resolved (`day9-monitoring-alert-drill.md`) | No notification channel (email/Slack) |
| 3.11 | Failure exercises | ✅ | Pod kill (all 200), database kill (one 503, recovered in 2 s), bad release + rollback, staging outage alert drill | |
| 3.12 | Runbooks | ✅ | `docs/runbooks.md` 1–10 (provision, connect, deploy, promote, rollback, teardown, monitoring/triage, backup/restore, drills) | |
| 3.13 | Security controls | ✅ | Non-root image, Trivy (fail on fixable critical), gitleaks, checkov (0 failed, documented exceptions), NetworkPolicies (proved by `up=0` before the policy change), IMDSv2, no SSH, only port 80 open, encrypted buckets | HTTP only (no TLS), see `security-exceptions.md` |
| 3.14 | Secrets management and rotation | 🟡 | DB passwords random, stored only in Kubernetes Secrets; Grafana admin password rotated after exposure (runbook 7) | No external secrets manager; DB password not rotated |
| 3.15 | Cost control and cleanup | 🟡 | AWS Free plan credits, budget alarm, host stopped between sessions; teardown runbook 6 | Final teardown to be run after the review recording |

## Scope notes

See `docs/decisions.md` (D-001 to D-020) for every design choice and trade-off,
`docs/security-exceptions.md` for accepted lab risks, and `docs/ai-assistance.md` for the
AI-use disclosure.
