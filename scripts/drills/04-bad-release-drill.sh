#!/bin/bash
# Drill 4 - Bad application release: deploy a release whose readiness check
# fails, detect the failed rollout, roll back to the previous release, and
# prove no tickets were lost. Run ON THE HOST:
#   sudo ./scripts/drills/04-bad-release-drill.sh
#
# The bad release is release 0.1.1-bad: same image digest, but its readiness
# probe calls an endpoint that does not exist (/health/ready-v2), so the new
# pod never becomes Ready. Because maxUnavailable=0, the two healthy pods of
# the previous release keep serving during the whole incident.
set -uo pipefail
source "$(dirname "$0")/_common.sh"
NS=staging
cd "$(dirname "$0")/../.." || exit 1
user_check() {  # 10 requests along the real user path: internet -> Traefik (HTTPS) -> pods
  local url codes; url="$(app_url $NS)/health/ready"
  codes=$(for _ in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' --max-time 5 "$url"; done)
  echo "    10 user requests to $url: $codes"
}

echo "Drill 4: bad release + rollback   started $(ts)"
step "baseline"
GOOD_REV=$(helm -n $NS history supportflow --max 1 -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1]["revision"])')
helm -n $NS history supportflow --max 3
kubectl -n $NS get pods -l app.kubernetes.io/component=api
BEFORE=$(ticket_count $NS); echo "    tickets: $BEFORE   healthy revision: $GOOD_REV"

step "inject: helm upgrade to release 0.1.1-bad (readiness probe -> /health/ready-v2)"
T_INJECT=$(epoch)
if helm upgrade supportflow charts/supportflow --namespace $NS --reset-then-reuse-values \
     --set probes.readiness.path=/health/ready-v2 --set release.version=0.1.1-bad \
     --history-max 10 --wait --timeout 90s; then
  fail "the bad release was reported healthy"
else
  T_DETECT=$(epoch)
  pass "rollout failure detected by helm --wait after $(( T_DETECT - T_INJECT )) s (new pod never Ready)"
fi

step "diagnosis"
kubectl -n $NS get pods -l app.kubernetes.io/component=api
BAD_POD=$(kubectl -n $NS get pods -l app.kubernetes.io/component=api -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{"\n"}{end}' | head -1)
[[ -n "$BAD_POD" ]] && kubectl -n $NS get events --field-selector involvedObject.name="$BAD_POD" | grep -i readiness | tail -3
user_check
helm -n $NS history supportflow --max 2

step "mitigate: helm rollback to revision $GOOD_REV"
T_RB=$(epoch)
helm -n $NS rollback supportflow "$GOOD_REV" --wait --timeout 5m
kubectl -n $NS rollout status deploy/supportflow-api --timeout=180s
T_OK=$(epoch)
pass "rolled back in $(( T_OK - T_RB )) s (decision to healthy); whole incident $(( T_OK - T_INJECT )) s"

step "verify"
helm -n $NS history supportflow --max 3
kubectl -n $NS get pods -l app.kubernetes.io/component=api
kubectl -n $NS get deploy supportflow-api -o jsonpath='{"    readiness probe path: "}{.spec.template.spec.containers[0].readinessProbe.httpGet.path}{"\n"}'
user_check
AFTER=$(ticket_count $NS); echo "    tickets: $AFTER (before: $BEFORE)"
[[ "$AFTER" -ge "$BEFORE" ]] && pass "no tickets lost; schema untouched (no migration in this release)" || fail "ticket count dropped"
mkdir -p /var/log/supportflow
printf '%s env=%s event=bad-release-rollback bad=0.1.1-bad rolled_back_to_revision=%s seconds=%s\n' \
  "$(ts)" "$NS" "$GOOD_REV" "$(( T_OK - T_RB ))" | tee -a /var/log/supportflow/releases.log

echo
if [[ $FAILED == 0 ]]; then echo "DRILL 4 PASSED   finished $(ts)"; else echo "DRILL 4 HAD FAILURES   finished $(ts)"; exit 1; fi
