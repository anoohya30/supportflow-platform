#!/bin/bash
# Disaster recovery: load the latest encrypted S3 backup into an environment's
# NEW, EMPTY database (for example after the host was replaced).
# Refuses to run if the database already contains tickets, so it can never
# overwrite a healthy database. Run ON THE HOST:
#   sudo ./scripts/recover-db.sh staging
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ENV_NAME="${1:?Usage: $0 <staging|production-lab>}"
REGION="eu-west-2"
ACCOUNT=$(aws sts get-caller-identity --region "$REGION" --query Account --output text)
BUCKET="supportflow-backups-$ACCOUNT"
T0=$(date -u +%s)
psql_in() { kubectl -n "$ENV_NAME" exec -i statefulset/postgres -- psql -U supportflow -v ON_ERROR_STOP=1 "$@"; }

EXISTING=$(psql_in -d supportflow -tA -c "select count(*) from tickets;" 2>/dev/null || echo 0)
if [[ "$EXISTING" -gt 0 ]]; then
  echo "ABORT: $ENV_NAME database already has $EXISTING tickets. This script only fills an EMPTY database."
  exit 1
fi

KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$ENV_NAME/" --region "$REGION" \
  --query 'sort_by(Contents,&LastModified)[-1].Key' --output text)
BACKUP_AT=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" --query LastModified --output text)
echo "==> [$ENV_NAME] latest backup: $KEY (written $BACKUP_AT)"

echo "==> [$ENV_NAME] stop the API while the data is loaded"
kubectl -n "$ENV_NAME" scale deploy/supportflow-api --replicas=0
kubectl -n "$ENV_NAME" wait --for=delete pod -l app.kubernetes.io/component=api --timeout=120s || true

echo "==> [$ENV_NAME] pg_restore into the empty database"
aws s3 cp "s3://$BUCKET/$KEY" - --region "$REGION" --only-show-errors \
  | kubectl -n "$ENV_NAME" exec -i statefulset/postgres -- \
      pg_restore -U supportflow -d supportflow --clean --if-exists --no-owner --exit-on-error

echo "==> [$ENV_NAME] start the API again"
kubectl -n "$ENV_NAME" scale deploy/supportflow-api --replicas=2
kubectl -n "$ENV_NAME" rollout status deploy/supportflow-api --timeout=180s

TICKETS=$(psql_in -d supportflow -tA -c "select count(*) from tickets;")
MAXID=$(psql_in -d supportflow -tA -c "select max(id) from tickets;")
ALEMBIC=$(psql_in -d supportflow -tA -c "select version_num from alembic_version;")
mkdir -p /var/log/supportflow
printf '%s env=%s event=recovered-from-backup key=%s backup_at=%s tickets=%s max_id=%s alembic=%s seconds=%s\n' \
  "$(date -u +%FT%TZ)" "$ENV_NAME" "$KEY" "$BACKUP_AT" "$TICKETS" "$MAXID" "$ALEMBIC" "$(( $(date -u +%s) - T0 ))" \
  | tee -a /var/log/supportflow/restores.log
echo "RECOVERED $ENV_NAME: $TICKETS tickets from the backup written $BACKUP_AT"
