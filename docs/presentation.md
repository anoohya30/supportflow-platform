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
HTTPS with a trusted Let's Encrypt certificate (ports 443 + 80 redirect only); admin UIs only through an SSM tunnel. IMDSv2, non-root container,
NetworkPolicies, encrypted and private buckets, secret scanning on every PR, checkov with
documented exceptions. NetworkPolicy negative tests 6/6. Database password rotation with
proof that the old credential is rejected; the Grafana password was rotated after exposure.

## 5. Measured results
| Target | Result |
|---|---|
| 10 min @ 20 req/s, 80 % reads / 20 % creates, p95 < 500 ms, 5xx < 1%, 2 replicas | 12,000 requests, 79.9 / 20.1 %, **p95 30.94 ms**, **0.00 % 5xx** (HTTPS, production-lab) |
| Rollback < 5 min (release that fails readiness) | detected 97 s, **rolled back in 2 s**, users saw only 200 |
| Restore to fresh DB < 30 min, reconnect the API | **RTO 12 s**, 6 ticket IDs identical, read through the API |
| RPO <= 15 min | backups every 15 min; **303 s** at recovery start |
| Alerting (1 min / 1 min / 5xx over 2 min) | FIRING notification 91 s (no replicas) and 83 s (database) after injection, then RESOLVED |

## 6. Recovery demonstrations
Scripted drills (`scripts/drills/`, all passed on 27 Oct): NetworkPolicy negative tests,
alert notification, database outage (ready 503, live 200, no restarts), readiness-failing
release + rollback, restore + reconnect, credential rotation. Earlier: API pod killed under
load (users saw only 200). Evidence: [day11-review-fixes-drills.md](evidence/day11-review-fixes-drills.md).

**Real incident (27 Oct):** a Terraform apply replaced the host and deleted its disk. The
platform was rebuilt from the repository and both databases recovered from S3 with no
ticket loss. The blameless report includes the clean-room result:
[incident-2026-10-27-host-replaced.md](incident-2026-10-27-host-replaced.md).

## 7. Cost
| | Amount (USD) |
|---|---|
| Estimate for the lab period (host about 6 h running, disk + public IP for about 6 days, S3/ECR) | about 2 to 3 |
| Observed (actual AWS usage cost from Cost Explorer, 1 Sep to today; fully covered by Free plan credits, 138.12 credit still left) | **$0.95** |

Budget alarm at USD 25 (counts usage before credits). The host now stays running during
the review window (about USD 2.50/day from credits). Final teardown (runbook 6) only after
the assessor confirms the review is finished.

## 8. Remaining limitations (not completed)
- Reviewer-enforced promotion gate: needs the assessor's GitHub identity; promotion is
  still a manual, logged command.
- Argo CD / GitOps reconciliation and the GitOps drift exercise (deploys use Helm from the host).
- AWS Secrets Manager (secrets are random Kubernetes Secrets, rotated by runbook 11).
- Scheduled Terraform drift check; database data on the host disk (see the incident report).
- Notifications go to a local webhook collector only (nobody is paged).

Full requirement-to-evidence matrix: [docs/acceptance-evidence.md](acceptance-evidence.md).
