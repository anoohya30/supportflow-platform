#!/bin/bash
# Turn on HTTPS for both environments (lab host). Run ON THE HOST, after
# "terraform apply" has opened port 443 in the security group:
#
#   sudo ./scripts/enable-https.sh
#
# 1. Upgrade both Helm releases so their Ingress uses HTTPS (same image,
#    same settings: --reset-then-reuse-values keeps the deployed digest).
# 2. Configure Traefik with a Let's Encrypt resolver + HTTP->HTTPS redirect.
# 3. Wait until each URL answers over HTTPS with a TRUSTED certificate
#    (curl verifies the certificate; TLS verification is never disabled).
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
cd "$(dirname "$0")/.."

TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
IP_DASHED=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 | tr '.' '-')

# Order matters (incident 2026-10-27): switch the Ingresses to HTTPS FIRST,
# so that when Traefik asks Let's Encrypt for a certificate, no plain-HTTP
# app route can answer the challenge URL with the app's 404.
for ENV_NAME in staging production-lab; do
  echo "==> [$ENV_NAME] Helm upgrade (Ingress -> HTTPS, image unchanged)"
  helm upgrade supportflow charts/supportflow --namespace "$ENV_NAME" \
    --reset-then-reuse-values --history-max 10 --wait --timeout 5m >/dev/null
  helm -n "$ENV_NAME" history supportflow --max 1
done

echo "==> Traefik: Let's Encrypt resolver + HTTP->HTTPS redirect"
kubectl apply -f k8s/traefik-config.yaml
sleep 20   # k3s helm-controller re-renders the Traefik chart
kubectl -n kube-system rollout status deploy/traefik --timeout=300s
sleep 20   # let the old Traefik pod disappear (it cannot answer challenges)

trusted() { curl -sS --max-time 10 -o /dev/null "$1/health/ready" 2>/dev/null; }
for PREFIX in staging prod; do
  URL="https://$PREFIX.$IP_DASHED.sslip.io"
  NS=$([[ $PREFIX == staging ]] && echo staging || echo production-lab)
  echo "==> waiting for a trusted certificate on $URL"
  for attempt in 1 2 3; do
    for _ in $(seq 1 9); do trusted "$URL" && break 2; sleep 10; done
    # A failed ACME order is only retried when Traefik's routes change, so
    # change a real router setting (priority) to trigger a new attempt.
    echo "    no trusted certificate yet: retry $attempt (route change)"
    kubectl -n "$NS" annotate ingress supportflow-api \
      traefik.ingress.kubernetes.io/router.priority="$((1000 + attempt))" --overwrite >/dev/null
  done
  if ! trusted "$URL"; then
    echo "HTTPS FAILED for $URL: kubectl -n kube-system logs deploy/traefik | grep -i acme"
    exit 1
  fi
  curl -sS -o /dev/null -w "    HTTPS $URL/health/ready -> %{http_code} (certificate verified by curl)\n" "$URL/health/ready"
  curl -sS -o /dev/null -w "    HTTP  redirect -> %{http_code} %{redirect_url}\n" "http://$PREFIX.$IP_DASHED.sslip.io/health/ready"
  echo | openssl s_client -connect "$PREFIX.$IP_DASHED.sslip.io:443" -servername "$PREFIX.$IP_DASHED.sslip.io" 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates | sed 's/^/    /'
done
echo "HTTPS ENABLED"
