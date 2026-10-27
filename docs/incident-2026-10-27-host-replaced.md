# Incident report: lab host replaced by a Terraform apply (2026-10-27)

**Format:** blameless. The goal is to understand how the system and the
process allowed this, not who pressed the button.
**Environment:** lab only (staging and production-lab on one EC2 host). No
real customers. All times UTC.

## Summary

While adding an HTTPS (443) security-group rule, `terraform apply` also
**replaced the EC2 lab host**. The old host and its root disk (k3s, both
PostgreSQL databases, monitoring) were deleted. Both environments were
offline for about 36 minutes and served only an untrusted certificate for
another ~16 minutes. The platform was rebuilt from the repository onto the
new host and **both databases were recovered from the encrypted S3 backups
with no ticket loss** (no writes happened after the last backup).

| | |
|---|---|
| Impact | staging + production-lab unavailable 17:28 to 18:04; HTTPS warning until ~18:22 |
| Data loss | none observed. Backups from 17:15 were restored (RPO window 13 min, no writes in it) |
| Detection | operator saw `aws_instance.host: Destroying...` in the apply output |
| Recovery | `scripts/rebuild-host.sh` + `scripts/recover-db.sh` (runbook 13) |
| Severity | high for the lab (full outage, data at risk); no customer impact |

## Timeline

| Time (UTC) | Event |
|---|---|
| 17:15 | Host started after being stopped; scheduled backup catch-up writes `staging/supportflow-20261027T171525Z.dump` and `production-lab/...171527Z.dump` |
| 17:19 | Platform healthy (`/health/ready` 200) |
| 17:25 | PR #28 merged: HTTPS ingress config, port 443 rule, alerts, drills |
| ~17:27 | `terraform plan -out=tfplan` followed by `terraform apply tfplan` in one paste; the plan was not read before the apply |
| 17:28 | **Host destroyed** (`i-0945...`), new host created (`i-0139...`), Elastic IP moved to the new host. The 443 rule failed (`Invalid rule description`: an apostrophe). **Outage starts** |
| 17:29 | Detected from the apply output. Decision: do not apply again until the cause is fixed |
| 17:35 | PR #29 merged: `lifecycle { ignore_changes = [ami] }`, description fixed, rebuild and recovery scripts added. New plan: `1 to add, 0 to change, 0 to destroy`; applied |
| 17:39 | First rebuild attempt in a foreground Session Manager shell. Output was buffered, so the session looked idle and was closed by Session Manager; nothing had been deployed |
| 18:03 | Rebuild restarted in the background (`nohup`, unbuffered log) |
| 18:04:23 | staging database recovered from the 17:15:26 backup: **2,525 tickets**, 8 s |
| 18:04:32 | production-lab database recovered from the 17:15:29 backup: **1,006 tickets**, 9 s. **Apps serving again (HTTP)** |
| 18:05 | Monitoring, notifications and the 15-minute backup timer installed (the timer only after the data was back) |
| 18:06 | HTTPS step: Let's Encrypt challenge answered by the app (404) because the Ingresses were switched to HTTPS after Traefik had already asked; browsers saw a self-signed certificate |
| 18:14 / 18:18 | Retries failed: Traefik was restarting, or an old Traefik pod without the challenge token answered |
| ~18:21 | With one Traefik pod running, a route change triggered a new order; certificate issued by Let's Encrypt (valid to 2027-01-25). HTTP redirect target also fixed (`:443`, not internal `:8443`) |
| ~18:22 | `curl` (certificate verified) returns 200 on both URLs. **Incident over** |

## Contributing causes

1. **The image selection was not pinned.** `data "aws_ami" "ubuntu"` uses
   `most_recent = true`. Canonical had published a newer Ubuntu 24.04 image
   since the host was built, so *any* apply wanted to replace the host,
   even one meant to add a single firewall rule.
2. **State lived on the host's root disk.** PostgreSQL data was on the
   instance root volume (`delete_on_termination = true`), so replacing the
   instance deleted the databases. Only the S3 backups survived.
3. **The plan was not reviewed before the apply.** Plan and apply ran in the
   same paste, so the `1 to destroy` line was never read. The workflow had no
   hard stop between the two.
4. **No scheduled drift check.** A daily `terraform plan` would have shown
   "host will be replaced" days earlier, as a warning instead of a surprise.
5. Recovery was slowed by two tooling gaps: a long script run in the
   foreground of a Session Manager shell (idle timeout), and an HTTPS
   script that requested certificates before the app routes had moved to HTTPS.

## What went well

- The 15-minute S3 backups, plus the catch-up backup at boot, meant recovery
  lost no data. Each database restore took under 10 seconds.
- The Elastic IP kept the URLs unchanged.
- Images in ECR are deployed by digest, so the rebuild ran exactly the
  artifact that CI had tested.
- The rebuild ran from the repository alone (see the clean-room result below).

## Prevention actions

| # | Action | Status |
|---|---|---|
| 1 | Ignore AMI changes on the running host; rebuilds only through a deliberate `terraform apply -replace=aws_instance.host` | ✅ PR #29 |
| 2 | Runbook rule: run `plan` alone, read the summary, **abort if anything is destroyed or replaced**, then apply the saved plan | ✅ runbook 1 |
| 3 | `rebuild-host.sh` + `recover-db.sh` (refuses to overwrite a database that has data); backup timer installed only after recovery | ✅ PR #29 |
| 4 | Long host jobs run under `nohup` with unbuffered logs | ✅ runbooks 9 and 13 |
| 5 | `enable-https.sh`: switch Ingresses first, wait for a single Traefik pod, retry with a route change; redirect to `:443` | ✅ this PR |
| 6 | Scheduled `terraform plan` drift check in CI (daily, read-only role) | ❌ open |
| 7 | Move PostgreSQL data to a separate EBS volume (or a managed database) so a host replacement does not delete it | ❌ open (cost, D-007) |
| 8 | Copy backups to a second region | ❌ open |

## Clean-room reproduction result

The rebuild was a reproduction from the repository onto a brand-new host
(fresh OS image, empty disk), by the same operator. It was not done by an
independent assessor.

| Step | Source | Result |
|---|---|---|
| Infrastructure | `infra/platform` (Terraform) | new instance + 443 rule, no manual console changes |
| k3s, Helm, namespaces, ECR pull secret | `user-data.sh.tftpl` (first boot) | ready without manual steps |
| Both environments, same digest | `scripts/deploy-env.sh` via `rebuild-host.sh` | deployed, migration Job ran |
| Data | `scripts/recover-db.sh` from S3 | 2,525 and 1,006 tickets |
| Monitoring, alerts, notifications | `scripts/install-monitoring.sh` | all pods Running |
| Backups | `scripts/install-backup-timer.sh` | next run 18:15 |
| HTTPS | `scripts/enable-https.sh` | needed 3 manual retries (fixed in this PR) |
| Verification | `scripts/drills/run-all.sh` | see `docs/evidence/day11-review-fixes-drills.md` |

Time from a clean host to serving again: about 2 minutes of script runtime
for deploy + recovery (18:03 to 18:04:32), once the first-boot install had
finished. Including the failed first attempt and the HTTPS fixes, the
wall-clock time was about 54 minutes.
