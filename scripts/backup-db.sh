#!/bin/bash
# Logical backup of one environment's PostgreSQL database to the encrypted
# S3 backups bucket. Run ON THE HOST:
#
#   sudo ./scripts/backup-db.sh staging
#   sudo ./scripts/backup-db.sh production-lab
#
# Uses the host's IAM role (no keys). Old backups expire by bucket lifecycle.
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ENV_NAME="${1:?Usage: $0 <staging|production-lab>}"
REGION="eu-west-2"

ACCOUNT=$(aws sts get-caller-identity --region "$REGION" --query Account --output text)
BUCKET="supportflow-backups-$ACCOUNT"
KEY="$ENV_NAME/supportflow-$(date -u +%Y%m%dT%H%M%SZ).dump"

echo "==> [$ENV_NAME] pg_dump -> s3://<backups-bucket>/$KEY"
kubectl -n "$ENV_NAME" exec statefulset/postgres -- \
  pg_dump -U supportflow -d supportflow --format=custom \
  | aws s3 cp - "s3://$BUCKET/$KEY" --region "$REGION" --sse AES256 --only-show-errors

SIZE=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" \
  --query ContentLength --output text)
TICKETS=$(kubectl -n "$ENV_NAME" exec statefulset/postgres -- \
  psql -U supportflow -d supportflow -tA -c "select count(*) from tickets;")

mkdir -p /var/log/supportflow
printf '%s env=%s key=%s bytes=%s tickets=%s\n' \
  "$(date -u +%FT%TZ)" "$ENV_NAME" "$KEY" "$SIZE" "$TICKETS" \
  | tee -a /var/log/supportflow/backups.log
echo "BACKUP OK"
