#!/bin/bash
# Restore drill: restore a backup from S3 into a SEPARATE scratch database
# (supportflow_restore_check) in the same environment, then compare the
# ticket count with the live database. The live database is never touched.
# Run ON THE HOST:
#
#   sudo ./scripts/restore-db.sh staging              # newest backup
#   sudo ./scripts/restore-db.sh staging <s3-key>     # a specific backup
#
# KEEP=1 keeps the scratch database afterwards (default: dropped).
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ENV_NAME="${1:?Usage: $0 <staging|production-lab> [s3-key]}"
KEY="${2:-}"
REGION="eu-west-2"
SCRATCH="supportflow_restore_check"

ACCOUNT=$(aws sts get-caller-identity --region "$REGION" --query Account --output text)
BUCKET="supportflow-backups-$ACCOUNT"

if [[ -z "$KEY" ]]; then
  KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$ENV_NAME/" --region "$REGION" \
    --query 'sort_by(Contents,&LastModified)[-1].Key' --output text)
fi
if [[ -z "$KEY" || "$KEY" == "None" ]]; then
  echo "ERROR: no backup found for $ENV_NAME. Run scripts/backup-db.sh $ENV_NAME first."
  exit 1
fi

psql_in() { kubectl -n "$ENV_NAME" exec statefulset/postgres -- psql -U supportflow -v ON_ERROR_STOP=1 "$@"; }

echo "==> [$ENV_NAME] restoring $KEY into scratch database $SCRATCH"
psql_in -d supportflow -q -c "DROP DATABASE IF EXISTS $SCRATCH;"
psql_in -d supportflow -q -c "CREATE DATABASE $SCRATCH;"
aws s3 cp "s3://$BUCKET/$KEY" - --region "$REGION" --only-show-errors \
  | kubectl -n "$ENV_NAME" exec -i statefulset/postgres -- \
      pg_restore -U supportflow -d "$SCRATCH" --no-owner --exit-on-error

LIVE=$(psql_in -d supportflow -tA -c "select count(*) from tickets;")
RESTORED=$(psql_in -d "$SCRATCH" -tA -c "select count(*) from tickets;")
VERSION=$(psql_in -d "$SCRATCH" -tA -c "select version_num from alembic_version;")
echo "    live tickets:     $LIVE"
echo "    restored tickets: $RESTORED"
echo "    restored schema:  alembic $VERSION"

if [[ "${KEEP:-0}" != "1" ]]; then
  psql_in -d supportflow -q -c "DROP DATABASE $SCRATCH;"
  echo "    scratch database dropped"
fi

printf '%s env=%s key=%s live=%s restored=%s alembic=%s\n' \
  "$(date -u +%FT%TZ)" "$ENV_NAME" "$KEY" "$LIVE" "$RESTORED" "$VERSION" \
  | tee -a /var/log/supportflow/restores.log

if [[ "$RESTORED" -gt 0 ]]; then
  echo "RESTORE VERIFIED (restored data readable; differences = tickets created after the backup)"
else
  echo "RESTORE FAILED: no tickets in restored database"
  exit 1
fi
