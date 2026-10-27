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
9. Failure drills (scripted, `scripts/drills/`)
10. Not yet implemented
11. Rotate the database password
12. HTTPS certificates (Let's Encrypt via Traefik)
13. Rebuild a lost host from the repository (disaster recovery / clean room)

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
terraform plan -out=tfplan | tail -20
# STOP. Read the "Plan:" line. Changes to an EXISTING platform must show
# "0 to destroy" and no "must be replaced". Only then, as a separate step:
terraform apply tfplan
terraform output -raw instance_id; echo
rm -f tfplan             # never commit saved plans
```
Never paste `plan` and `apply` together (incident 2026-10-27). Rebuilding
the host is a deliberate action: `terraform apply -replace=aws_instance.host`
followed by runbook 13. Don't print the full `terraform output`: it shows the
account number.
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

**Abort if:** the plan wants to *destroy* or *replace* anything you did not expect, or
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
python scripts/smoke_test.py --base-url https://staging.<ip-with-dashes>.sslip.io
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
**Rehearsed:** `sudo ./scripts/drills/04-bad-release-drill.sh` deploys a
release whose readiness check fails, detects the failed rollout (`helm --wait`
times out, the new pod never becomes Ready while the two old pods keep
serving because `maxUnavailable: 0`), rolls back and checks the ticket count.
Evidence: `docs/evidence/day11-review-fixes-drills.md`.

**Escalate if:** the rollback itself does not become Ready within 5 minutes,
or the ticket count dropped: stop deploying and use runbook 8.

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

**Open the UIs from your laptop** (no public port; Session Manager tunnel to
the host's private IP, e.g. 10.20.1.134):
```bash
aws ssm start-session --target <instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<host-private-ip>"],"portNumber":["30300"],"localPortNumber":["3000"]}'
# Grafana:      http://localhost:3000/d/supportflow   (user admin)
# Prometheus:   portNumber 30090 -> localPortNumber 9090
# Alertmanager: portNumber 30093 -> localPortNumber 9093
```
Keep that terminal open while you use the UI; Ctrl+C closes the tunnel.
Grafana password (on the host, never paste it anywhere):
`kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo`

**Rotate the Grafana admin password** (also do this if it was ever exposed):
```bash
kubectl -n monitoring delete secret grafana-admin
./scripts/install-monitoring.sh                      # creates a new random password
kubectl -n monitoring rollout restart deploy/monitoring-grafana
kubectl -n monitoring rollout status deploy/monitoring-grafana
```
(Grafana has no persistent volume, so the restarted pod starts with the new password.)

**Check from the host without a browser:**
```bash
NODE_IP=$(hostname -I | awk '{print $1}')
curl -s "http://$NODE_IP:30090/api/v1/query?query=up%7Bjob%3D%22supportflow%22%7D" | jq -r '.data.result[] | "\(.metric.environment) \(.metric.pod) up=\(.value[1])"'
curl -s "http://$NODE_IP:30090/api/v1/alerts" | jq -r '.data.alerts[] | "\(.labels.alertname) \(.labels.namespace) \(.state)"'
```

Dashboard: **Dashboards -> SupportFlow** (available pods, targets up,
requests/s, 5xx/s, p95 latency, status codes).

**Alerts** (`monitoring/kube-prometheus-stack-values.yaml`):

| Alert | Fires when | Severity |
|---|---|---|
| SupportFlowNoAvailablePods | 0 available API pods for 1 min | critical |
| SupportFlowReplicasDegraded | fewer pods than desired for 5 min | warning |
| SupportFlowDatabaseDown | PostgreSQL not ready for 1 min | critical |
| SupportFlowHighErrorRate | > 5% of requests are 5xx over 2 min, sustained 2 min, only while traffic > 0.2 req/s (minimum-traffic rule) | critical |
| SupportFlowHighLatencyP95 | p95 > 500 ms for 10 min | warning |

**Triage:**
1. Prometheus -> Alerts: which alert, which `namespace`/`environment`.
2. `kubectl -n <env> get pods` and `kubectl -n <env> describe pod <pod>`
   (look at Events: ImagePullBackOff, CrashLoopBackOff, OOMKilled).
3. `kubectl -n <env> logs deploy/supportflow-api --tail=50` (JSON logs with request IDs).
4. Recent release? `helm -n <env> history supportflow` -> roll back (runbook 5).
5. Database? `kubectl -n <env> get pods -l app.kubernetes.io/name=postgres`.

**Notifications:** Alertmanager sends FIRING and RESOLVED notifications
(timestamps, severity, namespace and a link to this runbook) to the local
webhook collector `monitoring/alert-webhook.yaml` (lab only, nothing leaves
the cluster). Read them on the host:
```bash
kubectl -n monitoring logs deploy/alert-webhook
# received=2026-10-27T18:..Z status=FIRING alert=SupportFlowNoAvailablePods namespace=staging ... runbook=https://github.com/.../runbooks.md#7-...
```
Rehearsed by `scripts/drills/02-alert-notification-drill.sh` and
`03-database-outage-drill.sh`.

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

**Schedule (RPO 15 min):** `./scripts/install-backup-timer.sh`
(systemd timer every 15 minutes; catches up after the host was stopped).
Check: `systemctl list-timers supportflow-backup.timer --no-pager` and
`tail -4 /var/log/supportflow/backups.log`.

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

**Full recovery drill (fresh database + reconnect the API):**
`sudo ./scripts/drills/05-restore-reconnect-drill.sh` restores the newest
scheduled backup into a fresh database `supportflow_restored`, compares row
counts and selected ticket IDs (field by field), points the staging API at the
restored database, reads those tickets through the API, records RTO/RPO, then
points the API back at the original database (which is never overwritten).

**Host lost (database volume gone):** rebuild the host (runbook 13);
`scripts/recover-db.sh <env>` loads the newest backup into the new, EMPTY
database. It refuses to run if the database already has tickets.

---

## 9. Failure drills

| Drill | Command (host) | Expected |
|---|---|---|
| API pod killed | `kubectl -n staging delete pod <one supportflow-api pod>` | replacement pod Running in < 30 s; laptop uptime loop stays 200 |
| All API pods gone | `kubectl -n staging scale deploy/supportflow-api --replicas=0` | `SupportFlowNoAvailablePods` fires after ~1-2 min; scale back to 2 -> alert resolves |
| Database pod killed | `kubectl -n staging delete pod postgres-0` | `/health/ready` returns 503 briefly, then 200; data intact (count unchanged) |
| Bad release | see runbook 5 | release fails, old pods keep serving, rollback |
| **Scripted drills (27 Oct)** | `sudo ./scripts/drills/run-all.sh` (all, ~30 min) or `run-all.sh 04` | 01 NetworkPolicy negative tests, 02 alert notification, 03 database outage, 04 bad release + rollback, 05 restore + reconnect, 06 credential rotation. Logs: `/var/log/supportflow/drills/`, copied to S3 `evidence/` |

Run long jobs on the host with `nohup ... &` and watch with `tail -f`: a
Session Manager session closes after ~20 minutes without output and stops
anything running in the foreground.
| Load test (target 2.1) | laptop: `docker run --rm -i -u "$(id -u):$(id -g)" -e BASE_URL=https://staging.<ip-dashes>.sslip.io -v "$PWD/docs/evidence:/out" grafana/k6:1.8.1 run --quiet --summary-export=/out/day10-k6-summary.json - < load-tests/k6-tickets.js` | 10 min at 20 req/s; thresholds p95 < 500 ms and 5xx < 1% pass |

Uptime loop (laptop):
`for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " https://staging.<ip-dashes>.sslip.io/health/ready; sleep 2; done; echo`

---

## 10. Not yet implemented

| Item | Status |
|---|---|
| GitOps (Argo CD) reconciliation and drift exercise | ❌ Not completed |
| AWS Secrets Manager | ❌ Not completed: secrets are random values in Kubernetes Secrets, rotated by runbook 11 |
| Reviewer-controlled production promotion gate | ❌ Not completed: needs the assessor's GitHub identity |
| Off-host / cross-region backup copy | ❌ Not completed (single region bucket) |
| Alert notifications to email/Slack | 🟡 Local webhook collector only (allowed by the brief) |

See `docs/acceptance-evidence.md` for the full requirement status.

---

## 11. Rotate the database password

**Prerequisites:** host session (runbook 2), API healthy.
```bash
sudo ./scripts/drills/06-credential-rotation-drill.sh     # staging
```
What it does: generates a new random password, changes it in PostgreSQL
(sent on stdin, never on a command line), updates the `supportflow-db`
Secret (`postgres-password` + `database-url`), restarts the API, then proves
from inside an API pod that the **new** credential connects and the **old**
one is rejected (`password authentication failed`). Only 8-character SHA-256
fingerprints are printed, never a value.

**Validation:** `DRILL 6 PASSED`; `/health/ready` 200; ticket count unchanged.
**Abort / escalate if:** the API does not become Ready after the restart:
the Secret and the database disagree. Re-run the script (it reads the current
Secret) or set the password back with `ALTER USER` from the Secret value.
For production-lab, edit `NS=` in the script and run it in a quiet period.

---

## 12. HTTPS certificates (Let's Encrypt via Traefik)

`sudo ./scripts/enable-https.sh` (also step 7 of `rebuild-host.sh`):
1. upgrades both Helm releases so their Ingress serves only HTTPS
   (`websecure`, certificate resolver `le`);
2. applies `k8s/traefik-config.yaml`: Let's Encrypt HTTP-01 challenge on
   port 80, certificates stored in `/data/acme.json` on a persistent volume,
   every HTTP request redirected to HTTPS on 443;
3. waits until `curl` (which verifies the certificate) gets 200 and prints
   the issuer and expiry. Renewal is automatic (~30 days before expiry).

**Check:** `echo | openssl s_client -connect staging.<ip-dashes>.sslip.io:443 -servername staging.<ip-dashes>.sslip.io 2>/dev/null | openssl x509 -noout -issuer -dates`
**If the certificate stays self-signed:** `kubectl -n kube-system logs deploy/traefik | grep -i acme`.
A failed order is retried only when Traefik's routes change: make sure only
one Traefik pod is running, then
`kubectl -n <env> annotate ingress supportflow-api traefik.ingress.kubernetes.io/router.priority=1001 --overwrite`.
Never disable TLS verification to make a check pass.

---

## 13. Rebuild a lost host from the repository (disaster recovery / clean room)

Used on 2026-10-27 after the host was replaced (`docs/incident-2026-10-27-host-replaced.md`).
**Prerequisites:** Terraform applied (new instance running), images in ECR,
backups in S3.
```bash
aws ssm start-session --target "$(terraform -chdir=infra/platform output -raw instance_id)"
sudo -i
git clone https://github.com/anoohya30/supportflow-platform.git /opt/supportflow
cd /opt/supportflow
nohup bash -c "scripts/rebuild-host.sh 2>&1 | sed -u -E 's/[0-9]{12}/<account>/g' > /var/log/supportflow-rebuild.log" >/dev/null 2>&1 &
tail -f /var/log/supportflow-rebuild.log
```
Steps: wait for first boot (k3s, Helm) -> deploy both environments with the
newest CI image digest -> load the newest backup into each new empty database
-> monitoring + notifications -> 15-minute backup timer (only after the data
is back, so an empty database is never the "latest backup") -> HTTPS.

**Validation:** `RECOVERED <env>: N tickets`, `HTTPS ENABLED`,
`REBUILD COMPLETE`; smoke test both URLs; run `scripts/drills/run-all.sh`.
**Abort if:** `recover-db.sh` reports the database already has tickets
(never overwrite a database with data) or the newest backup is older than expected.

