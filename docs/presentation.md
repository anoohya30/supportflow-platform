# SupportFlow: DevOps assessment presentation

*Engineering assessment / portfolio project (SkillAnthem DEVOPS 01). Simulated company,
synthetic data. Anoohya Bhairavabatla, October 2026.*

## 1. The problem
A small support-ticket API must be delivered safely and kept running: reproducible
infrastructure, controlled releases of one tested artifact, monitoring and alerts, and
proven recovery (rollback, restore), measured against lab targets.

## 2. Architecture
FastAPI + PostgreSQL on k3s, on one EC2 host in eu-west-2, built with Terraform.
Two environments (`staging`, `production-lab`) and a `monitoring` namespace.
Diagram, data paths and trust boundaries: [docs/architecture.md](architecture.md).

## 3. Release flow
1. Branch -> pull request -> 4 required checks (lint, migrations, 19 tests; gitleaks;
   Terraform/Helm/Kubernetes/checkov; image build, non-root check, Trivy, SBOM).
2. Merge to `main` -> CI builds the image once and pushes it to ECR via GitHub OIDC.
3. `deploy-env.sh staging <image@sha256>` -> migration Job -> rolling update -> smoke test.
4. The same digest is promoted to production-lab and recorded in a release log.
5. Rollback: `helm rollback` (or redeploy the last good digest).

## 4. Security
No stored AWS keys in CI (OIDC, `main` only, immutable subject). No SSH; Session Manager.
Only port 80 open; admin UIs only through an SSM tunnel. IMDSv2, non-root container,
NetworkPolicies, encrypted and private buckets, secret scanning on every PR, checkov with
documented exceptions. One exposed credential (Grafana) was rotated.

## 5. Measured results
| Target | Result |
|---|---|
| 10 min @ 20 req/s, p95 < 500 ms, 5xx < 1%, 2 replicas | 12,001 requests, **p95 28.21 ms**, **0.00% 5xx** |
| Rollback < 5 min | < 3 min, no downtime (old pods kept serving) |
| Restore to fresh DB < 30 min | about 5 s, row counts matched |
| RPO <= 15 min | backups every 15 min, runs succeeded |
| Alerting | outage -> alert firing in 2 min -> resolved |

## 6. Recovery demonstrations
Bad release blocked and rolled back; API pod killed (users saw only 200);
database pod killed (one 503, recovered in 2 s, no data lost); backup restored into a
fresh database; staging outage alert drill. Evidence: [docs/evidence/](evidence/).

## 7. Cost
| | Amount (USD) |
|---|---|
| Estimate for the lab period (host about 6 h running, disk + public IP for about 6 days, S3/ECR) | about 2 to 3 |
| Observed (actual AWS usage cost from Cost Explorer, 1 Sep to today; fully covered by Free plan credits, 138.12 credit still left) | **$0.95** |

Host stopped between sessions; budget alarm at USD 25 (counts usage before credits).
Final teardown (runbook 6) after the review is confirmed.

## 8. Remaining limitations (not completed)
- Reviewer-enforced promotion gate (solo lab; promotion is a manual, logged command).
- Argo CD / GitOps reconciliation (deploys use Helm from the host).
- Alert notifications (email/Slack), scheduled drift detection, HTTPS, DB password rotation.

Full requirement-to-evidence matrix: [docs/acceptance-evidence.md](acceptance-evidence.md).
