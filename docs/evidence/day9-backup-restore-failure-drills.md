# Evidence: backup, restore drill and failure drills (Day 9, 2026-10-19)

All times on the host are UTC; laptop monitor times are UK time (UTC+1).

## 1. Backups to S3 (`scripts/backup-db.sh`)
pg_dump (custom format) streamed straight to the encrypted, versioned backups bucket
using the host IAM role (no keys). Bucket name omitted.

    2026-10-19T18:14:33Z env=staging        key=staging/supportflow-20261019T181431Z.dump        bytes=10360 tickets=1001
    2026-10-19T18:14:35Z env=production-lab key=production-lab/supportflow-20261019T181434Z.dump bytes=10424 tickets=1003

## 2. Restore drill (`scripts/restore-db.sh`, non-destructive)
Newest backup restored into a separate scratch database, compared with the live database,
then the scratch database was dropped. The live database was not touched.

    2026-10-19T18:14:54Z env=staging        live=1001 restored=1001 alembic=0001  RESTORE VERIFIED
    2026-10-19T18:14:58Z env=production-lab live=1003 restored=1003 alembic=0001  RESTORE VERIFIED

## 3. Scheduled backups (`scripts/install-backup-timer.sh`)

    NEXT                        UNIT                      ACTIVATES
    Tue 2026-10-20 02:15:00 UTC supportflow-backup.timer  supportflow-backup.service

Persistent=true: a backup missed while the lab host is stopped runs at the next boot.

## 4. Failure drills (staging), with a laptop uptime monitor on /health/ready every 2 s

| Drill | Host action (UTC) | What users saw (UK time) | Recovery |
|---|---|---|---|
| Kill one API pod | `kubectl delete pod supportflow-api-...` about 18:19:43 | all `200` from 19:19:30 to 19:20:27 | replacement pod Running within seconds; still 2/2 pods |
| Kill the database pod | `kubectl delete pod postgres-0` at 18:20:27 | one `503` at 19:20:29, then `200` | postgres Ready again at 18:20:29 (2 s); ticket count still 1001 |

An earlier database kill at 18:18:21 also recovered by 18:18:23 with 1001 tickets.

The single 503 is the readiness probe working as designed: while the database is
unreachable the API reports "not ready" instead of serving errors, and recovers on its own.
Data survives because PostgreSQL stores it on a persistent volume, not inside the pod.

## Limitations
- Backups are in the same AWS region as the host (no cross-region copy).
- No point-in-time recovery (whole dumps only).
- Single node: a node failure would take down both environments (accepted for the lab, D-007).
