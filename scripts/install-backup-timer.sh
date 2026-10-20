#!/bin/bash
# Schedule backups of both environments every 15 minutes (systemd timer),
# which meets the RPO target of 15 minutes (acceptance target 2.3).
# Persistent=true runs a missed backup at next boot (the lab host is often
# stopped overnight). Run ON THE HOST:  sudo ./scripts/install-backup-timer.sh
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cat > /etc/systemd/system/supportflow-backup.service <<UNIT
[Unit]
Description=SupportFlow database backup to S3
After=k3s.service

[Service]
Type=oneshot
ExecStart=$REPO_DIR/scripts/backup-db.sh staging
ExecStart=$REPO_DIR/scripts/backup-db.sh production-lab
UNIT

cat > /etc/systemd/system/supportflow-backup.timer <<'UNIT'
[Unit]
Description=Run SupportFlow database backups every 15 minutes

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now supportflow-backup.timer
systemctl list-timers supportflow-backup.timer --no-pager
