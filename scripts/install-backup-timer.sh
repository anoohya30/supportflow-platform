#!/bin/bash
# Schedule a daily backup of both environments (02:15 UTC, systemd timer).
# Persistent=true runs a missed backup at next boot (the lab host is often
# stopped overnight). Run ON THE HOST:  sudo ./scripts/install-backup-timer.sh
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cat > /etc/systemd/system/supportflow-backup.service <<UNIT
[Unit]
Description=SupportFlow daily database backup to S3
After=k3s.service

[Service]
Type=oneshot
ExecStart=$REPO_DIR/scripts/backup-db.sh staging
ExecStart=$REPO_DIR/scripts/backup-db.sh production-lab
UNIT

cat > /etc/systemd/system/supportflow-backup.timer <<'UNIT'
[Unit]
Description=Run SupportFlow database backups daily

[Timer]
OnCalendar=*-*-* 02:15:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now supportflow-backup.timer
systemctl list-timers supportflow-backup.timer --no-pager
