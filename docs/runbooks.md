# Runbooks

Step-by-step operating procedures for the SupportFlow lab platform.
Each runbook lists **prerequisites, commands, expected output, validation,
and when to stop (abort)**. Region: `eu-west-2`. Lab only, not production.

Contents:
1. Provision the platform
2. Connect to the lab host
3. Deploy to staging
4. Promote the same image to production-lab
5. Roll back a bad release
6. Teardown (delete everything)
7. Monitoring: open Grafana / Prometheus / Alertmanager, alert triage
8. Database backup and restore
9. Failure drills
10. Not yet implemented

---

## 1. Provision the platform

**Prerequisites:** Terraform ≥ 1.10, AWS CLI v2, Session Manager plugin, AWS
credentials for the lab IAM user (`aws sts get-caller-identity` works),
budget alert active.

**One-time: remote state bucket**
```bash
cd infra/bootstrap
terraform init
terraform apply          # review the plan, type: yes
terraform output state_bucket
```
Expected: `Apply complete! Resources: 6 added` and a bucket named
`supportflow-tfstate-<account-id>`.

**Platform**
```bash
cd ../platform
terraform init -backend-config="bucket=$(terraform -chdir=../bootstrap output -raw state_bucket)"
terraform plan -out=tfplan
terraform apply tfplan
terraform output
rm -f tfplan             # never commit saved plans
```
Expected: about 25 resources added; outputs show `instance_id`, `public_ip`,
`staging_url`, `production_lab_url`, `ecr_repository_url`,
`github_actions_role_arn`.

**Connect CI to AWS (one-time):**
```bash
gh variable set AWS_ROLE_ARN --body "$(terraform output -raw github_actions_role_arn)"
```

**Validation:** host bootstrap finished (about 3–5 minutes after apply):
```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
# on the host:
test -f /var/lib/supportflow-ready && echo READY
sudo tail -5 /var/log/supportflow-bootstrap.log
sudo k3s kubectl get nodes          # STATUS: Ready
```

**Abort if:** the plan wants to *destroy* anything you did not expect, or
`aws sts get-caller-identity` shows the root user or the wrong account.

---

## 2. Connect to the lab host

No SSH port is open. Access is through **AWS Session Manager** (authenticated
by your AWS credentials, logged in AWS).
```bash
aws ssm start-session --target <instance_id>
sudo -i
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```
First time only, get the deployment files onto the host:
```bash
git clone https://github.com/anoohya30/supportflow-platform.git /opt/supportflow
```
Later: `cd /opt/supportflow && git pull`.

**Abort if:** the session fails with `TargetNotConnected`. Wait 2 minutes
after boot; check the instance is running.

---

## 3. Deploy to staging

**Prerequisites:** a merged PR whose CI run on `main` published an image.
Get the digest reference from the CI run's **Summary** ("Image published"),
or list it:
```bash
aws ecr describe-images --repository-name supportflow \
  --query 'reverse(sort_by(imageDetails,&imagePushedAt))[0].[imageTags[0],imageDigest]' --output text
# image ref = <ecr_repository_url>@<imageDigest>
```

**On the host:**
```bash
cd /opt/supportflow && git pull
./scripts/deploy-env.sh staging <ecr_repo_url>@sha256:<digest> 0.1.0 <commit-sha>
./scripts/seed-env.sh staging          # first deploy only: 1,000 synthetic tickets
```
Expected: migration Job completes, 2 pods `Running`, and `/version` returns
the commit.

**Validation (from your laptop):**
```bash
python scripts/smoke_test.py --base-url http://staging.<ip-with-dashes>.sslip.io
```
Expected: `ALL CHECKS PASSED`.

**Abort if:** the migration Job fails (`kubectl -n staging logs job/supportflow-api-migrate`)
or the smoke test fails. Do NOT promote.

---

## 4. Promote the same image to production-lab

Rule: production-lab gets the **exact digest** that passed staging. Never
rebuild, never use a tag.
```bash
./scripts/deploy-env.sh production-lab <same image ref as staging> 0.1.0 <commit-sha>
./scripts/seed-env.sh production-lab   # first deploy only
```
**Validation (digest trace):**
```bash
for ns in staging production-lab; do
  kubectl -n $ns get deploy supportflow-api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
done
cat /var/log/supportflow/releases.log
```
Expected: both lines show the identical `@sha256:` digest.

**Approval gate:** see `docs/acceptance-evidence.md`. A reviewer-enforced gate
for this manual promotion is NOT implemented (solo lab).

---

## 5. Roll back a bad release

**Symptom:** after a deploy, `helm upgrade` times out, pods are not Ready,
or the smoke test fails.

**Option A, immediate (Helm keeps the previous release):**
```bash
helm -n <env> history supportflow
helm -n <env> rollback supportflow <previous-revision> --wait --timeout 5m
```
**Option B, redeploy the last known-good digest** (from
`/var/log/supportflow/releases.log`):
```bash
./scripts/deploy-env.sh <env> <last-good image@sha256:...> 0.1.0 <commit>
```
**Validation:** smoke test passes; ticket count unchanged:
```bash
kubectl -n <env> exec statefulset/postgres -- psql -U supportflow -d supportflow -t -c "select count(*) from tickets;"
```
**Note:** rollback changes the *application* only. Migrations are additive,
so the old version still runs against the new schema; the database is
never rolled back by this procedure.

---

## 6. Teardown (delete everything)

Run at the end of the review window. **Order matters.**
```bash
# 1. Platform (EC2, network, ECR incl. images, backup bucket, IAM, OIDC)
cd infra/platform
terraform destroy          # review, type: yes

# 2. State bucket (only after the platform is gone)
cd ../bootstrap
terraform destroy

# 3. CI variable
gh variable delete AWS_ROLE_ARN
```
**Verify nothing is left (all should print empty / no results):**
```bash
aws ec2 describe-instances --filters Name=tag:Project,Values=supportflow Name=instance-state-name,Values=running,stopped --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-volumes --filters Name=tag:Project,Values=supportflow --query 'Volumes[].VolumeId'
aws ec2 describe-addresses --filters Name=tag:Project,Values=supportflow --query 'Addresses[].PublicIp'
aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[].SnapshotId'
aws ecr describe-repositories --query 'repositories[].repositoryName'
aws s3 ls | grep supportflow
```
**Finally** (AWS console): delete the access key and the IAM user
`anoohya-lab-admin`; check Billing → Bills for the observed cost.

**Abort if:** `terraform destroy` lists resources that are not tagged
`Project=supportflow`.

---

## 7. Monitoring and alert triage

**What runs:** kube-prometheus-stack in namespace `monitoring` (Prometheus,
Alertmanager, Grafana, kube-state-metrics, node-exporter). Prometheus scrapes
`GET /metrics` from every API pod in `staging` and `production-lab`
(job `supportflow`, label `environment`).

**Install / upgrade (on the host):**
```bash
cd /opt/supportflow && git pull
./scripts/install-monitoring.sh
kubectl -n monitoring get pods          # all Running
```

**Open the UIs from your laptop** (no public port; Session Manager tunnel):
```bash
aws ssm start-session --target <instance_id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["30300"],"localPortNumber":["3000"]}'
# Grafana:      http://localhost:3000   (user admin)
# Prometheus:   portNumber 30090 -> http://localhost:9090
# Alertmanager: portNumber 30093 -> http://localhost:9093
```
Grafana password (on the host):
`kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo`

Dashboard: **Dashboards -> SupportFlow** (available pods, targets up,
requests/s, 5xx/s, p95 latency, status codes).

**Alerts** (`monitoring/kube-prometheus-stack-values.yaml`):

| Alert | Fires when | Severity |
|---|---|---|
| SupportFlowNoAvailablePods | 0 available API pods for 1 min | critical |
| SupportFlowReplicasDegraded | fewer pods than desired for 5 min | warning |
| SupportFlowDatabaseDown | PostgreSQL not ready for 2 min | critical |
| SupportFlowHighErrorRate | > 5% of requests are 5xx for 5 min | critical |
| SupportFlowHighLatencyP95 | p95 > 500 ms for 10 min | warning |

**Triage:**
1. Prometheus -> Alerts: which alert, which `namespace`/`environment`.
2. `kubectl -n <env> get pods` and `kubectl -n <env> describe pod <pod>`
   (look at Events: ImagePullBackOff, CrashLoopBackOff, OOMKilled).
3. `kubectl -n <env> logs deploy/supportflow-api --tail=50` (JSON logs with request IDs).
4. Recent release? `helm -n <env> history supportflow` -> roll back (runbook 5).
5. Database? `kubectl -n <env> get pods -l app.kubernetes.io/name=postgres`.

**Limitation:** Alertmanager has no notification receiver (no email/Slack
configured); alerts are visible in Prometheus and Alertmanager only.

---

## 8. Database backup and restore

**Backup** (on the host; uses the host IAM role, no keys):
```bash
./scripts/backup-db.sh staging
./scripts/backup-db.sh production-lab
cat /var/log/supportflow/backups.log
```
Writes a `pg_dump` (custom format) to the encrypted, versioned S3 backups
bucket under `<env>/supportflow-<timestamp>.dump`. Expected: `BACKUP OK`.

**Daily schedule (optional):** `./scripts/install-backup-timer.sh`
(systemd timer, 02:15 UTC, catches up after the host was stopped).

**Restore drill (non-destructive):**
```bash
./scripts/restore-db.sh staging            # newest backup
```
Restores into a separate scratch database `supportflow_restore_check`,
compares the ticket count with the live database, then drops the scratch
database. Expected: `RESTORE VERIFIED`.

**Real restore (data loss incident)** - only after the drill succeeded:
1. Stop writes: `kubectl -n <env> scale deploy/supportflow-api --replicas=0`
2. `KEEP=1 ./scripts/restore-db.sh <env> <s3-key>` (keeps the scratch DB)
3. Swap databases inside postgres (`ALTER DATABASE supportflow RENAME TO supportflow_broken;`
   then `ALTER DATABASE supportflow_restore_check RENAME TO supportflow;`)
4. `kubectl -n <env> scale deploy/supportflow-api --replicas=2`, smoke test.

**Abort if:** the drill does not print `RESTORE VERIFIED`.

---

## 9. Failure drills

| Drill | Command (host) | Expected |
|---|---|---|
| API pod killed | `kubectl -n staging delete pod <one supportflow-api pod>` | replacement pod Running in < 30 s; laptop uptime loop stays 200 |
| All API pods gone | `kubectl -n staging scale deploy/supportflow-api --replicas=0` | `SupportFlowNoAvailablePods` fires after ~1-2 min; scale back to 2 -> alert resolves |
| Database pod killed | `kubectl -n staging delete pod postgres-0` | `/health/ready` returns 503 briefly, then 200; data intact (count unchanged) |
| Bad release | see runbook 5 | release fails, old pods keep serving, rollback |

Uptime loop (laptop):
`for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " http://staging.<ip-dashes>.sslip.io/health/ready; sleep 2; done; echo`

---

## 10. Not yet implemented

| Item | Status |
|---|---|
| Alert notifications (email/Slack) | ❌ Not completed (alerts visible in UI only) |
| Off-host / cross-region backup copy | ❌ Not completed (single region bucket) |
| Secret rotation | ❌ Not completed |

See `docs/acceptance-evidence.md` for the full requirement status.
