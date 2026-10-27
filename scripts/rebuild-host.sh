#!/bin/bash
# Rebuild everything on a NEW lab host from this repository, then recover
# both databases from the latest encrypted S3 backups. Used after the host
# was replaced (incident 2026-10-27) and as the clean-room reproduction.
# Run ON THE HOST, after cloning the repo to /opt/supportflow:
#   sudo /opt/supportflow/scripts/rebuild-host.sh 2>&1 | sed -E 's/[0-9]{12}/<account>/g' | tee /var/log/supportflow-rebuild.log
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
REGION="eu-west-2"
cd "$(dirname "$0")/.."
T0=$(date -u +%s)
stamp() { echo; echo "[$(date -u +%FT%TZ)] ==> $*"; }

stamp "1. wait for the first-boot script (k3s, Helm, namespaces)"
for _ in $(seq 1 60); do [[ -f /var/lib/supportflow-ready ]] && break; sleep 10; done
[[ -f /var/lib/supportflow-ready ]] || { echo "bootstrap not finished: see /var/log/supportflow-bootstrap.log"; exit 1; }
kubectl get nodes; k3s --version | head -1; helm version --short

stamp "2. newest image built by CI (deployed by digest)"
ACCOUNT=$(aws sts get-caller-identity --region "$REGION" --query Account --output text)
read -r TAG DIGEST < <(aws ecr describe-images --repository-name supportflow --region "$REGION" \
  --query 'reverse(sort_by(imageDetails,&imagePushedAt))[0].[imageTags[0],imageDigest]' --output text)
IMAGE="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/supportflow@$DIGEST"
echo "    tag=$TAG digest=$DIGEST"

for ENV_NAME in staging production-lab; do
  stamp "3. deploy $ENV_NAME (same digest)"
  ./scripts/deploy-env.sh "$ENV_NAME" "$IMAGE" 0.1.0 "$TAG"
done

for ENV_NAME in staging production-lab; do
  stamp "4. recover the $ENV_NAME database from the latest S3 backup"
  ./scripts/recover-db.sh "$ENV_NAME" || echo "    (database already has data: recovery skipped)"
done

stamp "5. monitoring, alert rules and notifications"
./scripts/install-monitoring.sh

stamp "6. scheduled backups every 15 minutes (only now, after the data is back)"
./scripts/install-backup-timer.sh

stamp "7. HTTPS"
./scripts/enable-https.sh

stamp "REBUILD COMPLETE in $(( ($(date -u +%s) - T0) / 60 )) minutes"
