#!/bin/bash
# Install Prometheus + Grafana + Alertmanager (kube-prometheus-stack) on the
# k3s lab host, with the SupportFlow scrape config, alert rules and dashboard.
# Run ON THE HOST (through Session Manager), from the repo folder:
#
#   sudo ./scripts/install-monitoring.sh
#
# Safe to run again (upgrade in place).
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
CHART_VERSION="92.10.1"

cd "$(dirname "$0")/.."

echo "==> namespace"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "==> Grafana admin secret"
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -hex 16)" >/dev/null
  echo "    created (random password, stored only in Kubernetes)"
else
  echo "    already exists (unchanged)"
fi

echo "==> SupportFlow dashboard"
kubectl -n monitoring create configmap supportflow-dashboard \
  --from-file=supportflow.json=monitoring/dashboards/supportflow.json \
  --dry-run=client -o yaml \
  | kubectl label --local -f - grafana_dashboard=1 -o yaml \
  | kubectl apply -f -

echo "==> Helm chart kube-prometheus-stack $CHART_VERSION"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" \
  --namespace monitoring \
  -f monitoring/kube-prometheus-stack-values.yaml \
  --wait --timeout 10m

echo "==> done"
kubectl -n monitoring get pods
echo
echo "Grafana user: admin   password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo"
echo "Open from your laptop with Session Manager port forwarding (runbook 7)."
