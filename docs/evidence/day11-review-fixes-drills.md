# Day 11 (2026-10-27): review fixes, failure drills, HTTPS, load test

Evidence for the points raised in the first review. All times UTC.
Lab: one EC2 host (k3s), `staging` and `production-lab`. Raw logs, with the
account number masked, are in `docs/evidence/day11-drills/`
(`scripts/drills/run-all.sh`, run 18:29 to 18:36).

| Review point | Fix | Evidence below | Result |
|---|---|---|---|
| No HTTPS | Let's Encrypt via Traefik, HTTP to HTTPS redirect (D-021) | §1 | ✅ trusted certificate, valid to 2027-01-25 |
| Alert timings | DB 1 min; 5xx > 5 % over 2 min with a minimum-traffic rule | §2 | ✅ |
| No notifications | Alertmanager to a local webhook collector (D-022) | §3, §4 | ✅ FIRING + RESOLVED with timestamps and runbook link |
| NetworkPolicy negative tests | drill 01 | §5 | ✅ 6/6 |
| Rollback used an invalid digest | drill 04: release that **fails readiness** | §6 | ✅ detected 97 s, rolled back 2 s, no user errors |
| Restore only compared counts | drill 05: fresh DB, ticket IDs, **API reconnected** | §7 | ✅ RPO 303 s, RTO 12 s |
| No credential rotation | drill 06 | §8 | ✅ old credential rejected |
| Load mix 80/20 | k6 script changed | §9 | ✅ 79.9 / 20.1 %, p95 30.94 ms, 0 % 5xx |
| Incident report, clean room | real incident on 27 Oct | `docs/incident-2026-10-27-host-replaced.md` | ✅ |
| URLs offline | host rebuilt and left running for the review | §1 | ✅ |

## 1. HTTPS (review: "no HTTPS/TLS")

```
$ echo | openssl s_client -connect staging.18-135-157-38.sslip.io:443 ... | openssl x509 -noout -issuer -dates
issuer=C = US, O = Let's Encrypt, CN = YR2
notBefore=Oct 27 17:23:41 2026 GMT
notAfter=Jan 25 17:23:40 2027 GMT

$ curl -sS -o /dev/null -w 'staging HTTPS: %{http_code}\n' https://staging.18-135-157-38.sslip.io/health/ready
staging HTTPS: 200          <- curl verifies the certificate (TLS verification never disabled)
prod HTTPS: 200
$ curl -si http://staging.18-135-157-38.sslip.io/health/ready | grep -i location
Location: https://staging.18-135-157-38.sslip.io/health/ready
```
Only ports 443 and 80 are open, both to Traefik; port 80 only redirects and
answers the ACME challenge. Renewal is automatic (Traefik renews ~30 days
before expiry; certificates are kept on a persistent volume). Issuing the
first certificate needed three retries; causes and fixes are in the incident
report and runbook 12.

## 2. Alert rules now match the brief

| Alert | Rule | Brief |
|---|---|---|
| SupportFlowNoAvailablePods | available replicas < 1 **for 1m** | no ready replicas for 1 min ✅ |
| SupportFlowDatabaseDown | PostgreSQL ready replicas < 1 **for 1m** (was 2m) | database unavailable 1 min ✅ |
| SupportFlowHighErrorRate | 5xx / all requests over **[2m] > 5 %, for 2m** (was 5m), **and** traffic > 0.2 req/s | 5xx > 5 % over 2 min; minimum-traffic rule ✅ |

Minimum-traffic rule: the ratio is evaluated only while an environment
receives more than 0.2 requests/s (12/min), so a single failed request at a
quiet time (1 of 2 = 50 %) cannot raise a misleading alert. Every alert has a
`runbook_url` annotation (runbook 7).

## 3. Drill 02: notification for "no ready API replicas" (staging)

| Time | Event |
|---|---|
| ~18:29:35 | staging API scaled to 0 (injected) |
| 18:30:52 | alert active in Prometheus (`startsAt`) |
| **18:31:03** | **FIRING** notification received by the webhook collector (**91 s** after injection: 1 min `for` + evaluation and scrape interval) |
| ~18:31:08 | API scaled back to 2, ready |
| 18:31:22 | alert ended (`endsAt`) |
| **18:32:03** | **RESOLVED** notification received (logged by the collector, shown in the drill 03 log) |

```
received=2026-10-27T18:31:03Z status=FIRING alert=SupportFlowNoAvailablePods namespace=staging severity=critical startsAt=2026-10-27T18:30:52.976Z endsAt=0001-01-01T00:00:00Z runbook=https://github.com/anoohya30/supportflow-platform/blob/main/docs/runbooks.md#7-monitoring-and-alert-triage
received=2026-10-27T18:32:03Z status=RESOLVED alert=SupportFlowNoAvailablePods namespace=staging severity=critical startsAt=2026-10-27T18:30:52.976Z endsAt=2026-10-27T18:31:22.976Z runbook=https://github.com/anoohya30/supportflow-platform/blob/main/docs/runbooks.md#7-monitoring-and-alert-triage
```
Tickets 2525 before and after. **Honest note:** the script reported "RESOLVED
received 5 s after recovery" because it matched the RESOLVED message of an
*earlier* run of the same alert (an accidental first run at 18:24, see the
end of this file). The RESOLVED message of this alert is the 18:32:03 line
above. The script now matches the RESOLVED message by the alert's `startsAt`.

## 4. Drill 03: database outage (staging)

| Step | Observation |
|---|---|
| Baseline | `/health/live` 200, `/health/ready` 200, API restart counts `0 0`, 2525 tickets |
| 18:31:13 inject | PostgreSQL StatefulSet scaled to 0 |
| First symptom | `/health/live` **200**, `/health/ready` **503**: readiness fails, liveness healthy |
| 18:32:33 detection | **FIRING** `SupportFlowDatabaseDown` (83 s after injection; rule 1 min) |
| No restart loop | API restart counts during the outage `0 0` (unchanged) |
| Mitigation | PostgreSQL started; service restored **6 s** later (`/health/ready` 200) |
| 18:33:33 | **RESOLVED** `SupportFlowDatabaseDown` |
| Verify | 2525 tickets (unchanged), restart counts `0 0` |

## 5. Drill 01: NetworkPolicy negative tests

| # | Path | Expected | Result |
|---|---|---|---|
| A | staging API pod to staging PostgreSQL :5432 | allowed | CONNECTED ✅ |
| B | unlabelled pod in staging to staging PostgreSQL | blocked | BLOCKED (refused) ✅ |
| C | pod in `default` namespace to staging PostgreSQL | blocked | BLOCKED ✅ |
| D | staging API pod to **production-lab** PostgreSQL (cross-environment) | blocked | BLOCKED ✅ |
| E | pod in `default` namespace to staging API pod :8000 directly | blocked | BLOCKED ✅ |
| F | `monitoring` namespace (Prometheus) to staging API pod :8000 | allowed | CONNECTED ✅ |

Plus: PostgreSQL has no public port (the security group allows only 80/443);
the Kubernetes API (6443) and the monitoring NodePorts are not open to the
internet (Session Manager only).

## 6. Drill 04: bad release that fails readiness, then rollback (staging)

The bad release `0.1.1-bad` uses the same image but a readiness check on an
endpoint that does not exist (`/health/ready-v2`).

| Time | Event |
|---|---|
| 18:33:34 | baseline: Helm revision 2 healthy, 2 pods Ready, 2525 tickets |
| 18:33:34 | `helm upgrade` to 0.1.1-bad |
| 18:35:11 | **detected**: `UPGRADE FAILED: context deadline exceeded` after 97 s; new pod `0/1 Running`, event `Readiness probe failed: HTTP probe failed with statuscode: 404` |
| during | 10 user requests over HTTPS: `200 x 10` (the two old pods kept serving because `maxUnavailable: 0`) |
| 18:35:12 | `helm rollback supportflow 2` |
| 18:35:14 | healthy again: **2 s** from the rollback decision, 100 s whole incident; Helm history `3 failed`, `4 deployed: Rollback to 2`; readiness path `/health/ready` |
| verify | 10 x 200; tickets 2525 (unchanged); no migration in the release, schema untouched |

## 7. Drill 05: restore into a fresh database and reconnect the API (staging)

| Step | Result |
|---|---|
| Latest scheduled backup | `staging/supportflow-20261027T183011Z.dump`, written 18:30:13, **AES256** (S3 SSE) |
| RPO at recovery start (18:35:16) | **303 s** (target ≤ 900 s) |
| Restore | into a **fresh** database `supportflow_restored` |
| Row counts | live 2525, restored 2525 |
| Selected ticket IDs | 1, 250, 500, 750, 1000, 2525: identical (md5 of id, subject, description, priority, created_at) |
| **API reconnected** | staging `DATABASE_URL` switched to `supportflow_restored` (value never printed), rollout |
| Read through the API | `GET /tickets/{1,250,500,750,1000,2525}` all 200 with the same subjects, `/health/ready` 200 |
| **RTO** | **12 s** from recovery start (target ≤ 1800 s) |
| Afterwards | API switched back to the original database (never overwritten), restored copy dropped, 2525 tickets |

Record: `2026-10-27T18:35:38Z env=staging key=staging/supportflow-20261027T183011Z.dump backup_at=2026-10-27T18:30:13+00:00 rpo_s=303 rto_s=12 live=2525 restored=2525 ids_match=yes api_reconnected=yes`

A real recovery onto an empty database, after the host was lost, is in the
incident report: 2,525 and 1,006 tickets recovered in 8 s and 9 s.

## 8. Drill 06: database credential rotation (staging)

```
old password fingerprint: d53e7565   new password fingerprint: c2883983
baseline: old credential: ACCEPTED
rotate: ALTER USER ... (password sent on stdin)
update Secret supportflow-db (postgres-password, database-url) + rollout restart
old credential: REJECTED (password authentication failed for user "supportflow")
new credential: ACCEPTED
secret fingerprint now: c2883983
tickets: 2525
```
Neither password was printed (only 8-character SHA-256 fingerprints); the test
connects from inside an API pod over the pod network, where PostgreSQL
requires password authentication. Runbook 11.

## 9. Load test with the 80 % read / 20 % create mix

Run from the laptop with Docker against **production-lab over HTTPS** (2 API replicas,
1,006+ seeded tickets), 18:42 to 18:52 UTC, while the drills ran on staging. Script:
`load-tests/k6-tickets.js` (50 % list + 30 % read one = reads; 20 % create).

| Measure | Target | Result |
|---|---|---|
| Duration / rate | 10 min at 20 req/s | 10m00s, **12,000 requests**, 19.99 req/s, 0 dropped |
| Mix | 80 % reads / 20 % creates | **9,592 reads (79.9 %) / 2,408 creates (20.1 %)** |
| p95 latency | < 500 ms | **30.94 ms** (avg 25.09, p99 40.43, max 207.2 ms) |
| Server errors (5xx) | < 1 % | **0.00 %** (0 of 12,000) |
| Validation errors (4xx), reported separately | n/a | **0** (`validation_errors` counter never incremented) |
| Checks | | 100 % (12,000 / 12,000) |

Raw output: `day11-k6-output.txt`; summary: `day11-k6-summary.json`.
Latency includes the home network round trip from the laptop.

## Note on the drill run

A first run of `run-all.sh` was started twice by accident (a pasted block ran
the command twice). The two copies interfered, so both were stopped at 18:28
and staging was returned to a healthy state. The clean run is 18:29:26 to
18:35:52, and its logs are the ones in `day11-drills/`. One drill 02 process
from the first copy finished by itself at 18:30:11, overlapping the clean
run's drill 01 (which still passed 6/6). That is why the drill 02 log also
shows an alert started at 18:25:52.
