#!/bin/bash
# Deploy one image (by digest) to one environment on the k3s lab host.
# Run ON THE HOST (through Session Manager), from the repo folder:
#
#   sudo ./scripts/deploy-env.sh staging        <image@sha256:...> <version> <commit>
#   sudo ./scripts/deploy-env.sh production-lab <image@sha256:...> <version> <commit>
#
# Steps: DB password secret (created once, never in Git) -> PostgreSQL ->
# ECR pull secret -> Helm (migration Job first, then rolling update) -> record.
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

ENV_NAME="${1:-}"
IMAGE_REF="${2:-}"
VERSION="${3:-0.1.0}"
COMMIT="${4:-unknown}"

case "$ENV_NAME" in
  staging) HOST_PREFIX="staging" ;;
  production-lab) HOST_PREFIX="prod" ;;
  *) echo "Usage: $0 <staging|production-lab> <image@sha256:digest> [version] [commit]"; exit 1 ;;
esac

if [[ "$IMAGE_REF" != *@sha256:* ]]; then
  echo "ERROR: image must be pinned by digest (repository@sha256:...), not a tag."
  exit 1
fi

cd "$(dirname "$0")/.."

# Public IP of this host (IMDSv2) -> app hostname on sslip.io
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PUBLIC_IP=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
APP_HOST="$HOST_PREFIX.$(echo "$PUBLIC_IP" | tr '.' '-').sslip.io"

echo "==> [$ENV_NAME] database secret"
if ! kubectl -n "$ENV_NAME" get secret supportflow-db >/dev/null 2>&1; then
  PW=$(openssl rand -hex 24)
  kubectl -n "$ENV_NAME" create secret generic supportflow-db \
    --from-literal=postgres-password="$PW" \
    --from-literal=database-url="postgresql+psycopg://supportflow:$PW@postgres:5432/supportflow" >/dev/null
  unset PW
  echo "    created (random password, stored only in Kubernetes)"
else
  echo "    already exists (unchanged)"
fi

echo "==> [$ENV_NAME] PostgreSQL"
kubectl -n "$ENV_NAME" apply -f k8s/postgres.yaml
kubectl -n "$ENV_NAME" rollout status statefulset/postgres --timeout=300s

echo "==> [$ENV_NAME] ECR pull secret"
/usr/local/bin/refresh-ecr-secret

echo "==> [$ENV_NAME] Helm release (migration Job runs first)"
helm upgrade --install supportflow charts/supportflow \
  --namespace "$ENV_NAME" \
  -f "charts/supportflow/values-$ENV_NAME.yaml" \
  --set image.ref="$IMAGE_REF" \
  --set ingress.host="$APP_HOST" \
  --set release.version="$VERSION" \
  --set release.commit="$COMMIT" \
  --history-max 10 \
  --wait --timeout 5m

# Release record (who/what/when) for the evidence trail.
mkdir -p /var/log/supportflow
printf '%s env=%s version=%s commit=%s image=%s operator=%s\n' \
  "$(date -u +%FT%TZ)" "$ENV_NAME" "$VERSION" "$COMMIT" "$IMAGE_REF" "${SUDO_USER:-$USER}" \
  | tee -a /var/log/supportflow/releases.log

echo "==> [$ENV_NAME] done"
kubectl -n "$ENV_NAME" get pods -o wide
echo
echo "App URL: https://$APP_HOST"
curl -sS "https://$APP_HOST/version" || echo "(HTTPS not ready yet: the certificate can take a minute on first issue)"; echo
