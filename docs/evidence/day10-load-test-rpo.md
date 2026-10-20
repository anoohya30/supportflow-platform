# Evidence: load test (target 2.1) and backup RPO (target 2.3) (Day 10, 2026-10-20)

## 1. Load test: 10 minutes at 20 requests/second against staging (2 replicas)

Tool: k6 1.8.1 (container `grafana/k6:1.8.1`), script `load-tests/k6-tickets.js`,
run from the laptop over the internet (internet -> Traefik -> API -> PostgreSQL).
Mix: 60% list, 25% read one, 10% create, 5% update status. Synthetic data only.
Full output: `day10-k6-output.txt`; machine-readable: `day10-k6-summary.json`.

| Metric | Target | Result |
|---|---|---|
| Requests | 10 min @ 20 req/s | 12,001 requests @ 20.0 req/s, 0 dropped |
| p95 latency | < 500 ms | **28.21 ms** (median 22.98 ms, p99 33 ms, max 243 ms) |
| 5xx errors | < 1% | **0.00%** (0 of 12,001) |
| Correct status codes (checks) | | 100% (12,001 of 12,001) |
| API replicas | 2 | 2 (staging Deployment) |

    THRESHOLDS
      checks             ✓ 'rate>0.99' rate=100.00%
      dropped_iterations ✓ 'count<60'  count=0
      http_req_duration  ✓ 'p(95)<500' p(95)=28.21ms
      server_errors      ✓ 'rate<0.01' rate=0.00%

A 30-second trial run beforehand gave the same picture (601 requests, p95 28.44 ms, 0 errors).
Test finished 2026-10-20 18:50:35 BST (17:50:35 UTC).

## 2. Backups every 15 minutes (RPO <= 15 min)

`scripts/install-backup-timer.sh` (D-019) installs a systemd timer `OnCalendar=*:0/15`,
`Persistent=true`.

    NEXT                        LEFT LAST                         UNIT
    Tue 2026-10-20 17:45:00 UTC 7min Tue 2026-10-20 17:35:11 UTC  supportflow-backup.timer

The 17:35:11 run was the automatic catch-up after the host started. The 17:45 run:

    Active: inactive (dead) since Tue 2026-10-20 17:45:19 UTC
    Process: ExecStart=/opt/supportflow/scripts/backup-db.sh staging        (code=exited, status=0/SUCCESS)
    Process: ExecStart=/opt/supportflow/scripts/backup-db.sh production-lab (code=exited, status=0/SUCCESS)

Restore time (target < 30 min) was measured on Day 9: about 5 seconds per environment into a
fresh database, with matching ticket counts (`day9-backup-restore-failure-drills.md`).

Limitation: backups run only while the lab host is running (it is stopped between work
sessions to save cost; no data changes while it is stopped).
