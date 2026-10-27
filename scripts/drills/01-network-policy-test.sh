#!/bin/bash
# Drill 1 - NetworkPolicy negative tests: allowed paths connect, disallowed
# paths are blocked. Run ON THE HOST:  sudo ./scripts/drills/01-network-policy-test.sh
set -uo pipefail
source "$(dirname "$0")/_common.sh"

PROBE='
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
try:
    socket.create_connection((host, port), 4).close()
    print(f"{host}:{port} CONNECTED")
except Exception as e:
    print(f"{host}:{port} BLOCKED ({type(e).__name__})")
'
# Throwaway pod (no SupportFlow labels) in a namespace, running the probe.
probe_from() {
  local ns="$1" host="$2" port="$3"
  kubectl -n "$ns" run "np-probe-$RANDOM" --image=python:3.12.7-slim --restart=Never --rm -i --quiet \
    --labels=app.kubernetes.io/name=np-probe --command -- python -c "$PROBE" "$host" "$port" 2>/dev/null | tail -1
}
expect() {  # expect <CONNECTED|BLOCKED> <description> <result line>
  echo "    result: $3"
  if [[ "$3" == *"$1"* ]]; then pass "$2 -> $1 (as expected)"; else fail "$2 -> expected $1"; fi
}

echo "Drill 1: NetworkPolicy negative tests   started $(ts)"
kubectl get networkpolicy -A

step "A. allowed: staging API pod -> staging PostgreSQL :5432"
expect CONNECTED "staging API -> staging postgres" "$(echo "$PROBE" | api_py staging postgres 5432)"

step "B. blocked: unlabelled pod in staging -> staging PostgreSQL :5432"
expect BLOCKED "other pod in staging -> staging postgres" "$(probe_from staging postgres 5432)"

step "C. blocked: pod in the default namespace -> staging PostgreSQL :5432"
expect BLOCKED "default namespace -> staging postgres" "$(probe_from default postgres.staging.svc.cluster.local 5432)"

step "D. blocked: staging API pod -> production-lab PostgreSQL :5432 (cross-environment)"
expect BLOCKED "staging API -> production-lab postgres" "$(echo "$PROBE" | api_py staging postgres.production-lab.svc.cluster.local 5432)"

API_IP=$(kubectl -n staging get pods -l app.kubernetes.io/component=api -o jsonpath='{.items[0].status.podIP}')
step "E. blocked: pod in the default namespace -> staging API pod directly ($API_IP:8000)"
expect BLOCKED "default namespace -> staging API pod" "$(probe_from default "$API_IP" 8000)"

step "F. allowed: the monitoring namespace (Prometheus) -> staging API pod :8000"
expect CONNECTED "monitoring namespace -> staging API pod" "$(probe_from monitoring "$API_IP" 8000)"

echo
if [[ $FAILED == 0 ]]; then echo "DRILL 1 PASSED   finished $(ts)"; else echo "DRILL 1 HAD FAILURES   finished $(ts)"; exit 1; fi
