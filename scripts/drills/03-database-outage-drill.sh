#!/bin/bash
# Drill 3 - Database outage: stop PostgreSQL in staging. Readiness must fail
# while liveness stays healthy (no restart loop); SupportFlowDatabaseDown
# fires after 1 minute and resolves after recovery; no tickets lost.
# Run ON THE HOST:  sudo ./scripts/drills/03-database-outage-drill.sh
set -uo pipefail
source "$(dirname "$0")/_common.sh"
NS=staging
HEALTH='
import urllib.request, urllib.error
for path in ("/health/live", "/health/ready"):
    try:
        code = urllib.request.urlopen("http://127.0.0.1:8000" + path, timeout=5).status
    except urllib.error.HTTPError as e:
        code = e.code
    print(f"    {path} -> {code}")
'
restarts() { kubectl -n $NS get pods -l app.kubernetes.io/component=api -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{" "}{end}'; }

echo "Drill 3: database outage   started $(ts)"
step "baseline"
BEFORE=$(ticket_count $NS); echo "    tickets: $BEFORE"
R_BEFORE=$(restarts); echo "    API container restart counts: $R_BEFORE"
echo "$HEALTH" | api_py $NS

SINCE=$(ts)
step "inject: stop PostgreSQL (scale statefulset to 0)"
T_INJECT=$(epoch)
kubectl -n $NS scale statefulset/postgres --replicas=0
kubectl -n $NS wait --for=delete pod/postgres-0 --timeout=120s
sleep 20

step "first symptom: readiness fails, liveness stays healthy"
echo "$HEALTH" | api_py $NS
kubectl -n $NS get pods -l app.kubernetes.io/component=api

step "detection: waiting for the SupportFlowDatabaseDown FIRING notification (rule: 1m)"
if wait_notification "status=FIRING alert=SupportFlowDatabaseDown namespace=$NS" "$SINCE" 420; then
  pass "database alert FIRING $(( $(epoch) - T_INJECT )) s after the injection"
else
  fail "no database alert within 7 minutes"
fi
R_DURING=$(restarts); echo "    API restart counts during the outage: $R_DURING (before: $R_BEFORE)"
[[ "$R_DURING" == "$R_BEFORE" ]] && pass "no restart loop (liveness does not depend on the database)" || fail "API restarted during the outage"

step "mitigate: start PostgreSQL again"
T_FIX=$(epoch)
kubectl -n $NS scale statefulset/postgres --replicas=1
kubectl -n $NS rollout status statefulset/postgres --timeout=300s
kubectl -n $NS wait --for=condition=Ready pod -l app.kubernetes.io/component=api --timeout=180s
echo "    service restored $(( $(epoch) - T_FIX )) s after starting PostgreSQL"
echo "$HEALTH" | api_py $NS

step "waiting for the RESOLVED notification"
if wait_notification "status=RESOLVED alert=SupportFlowDatabaseDown namespace=$NS" "$SINCE" 420; then
  pass "database alert RESOLVED"
else
  fail "no RESOLVED notification within 7 minutes"
fi

step "verify"
AFTER=$(ticket_count $NS); echo "    tickets: $AFTER (before: $BEFORE)"
[[ "$AFTER" -ge "$BEFORE" ]] && pass "no tickets lost" || fail "ticket count dropped"
echo "    API restart counts after: $(restarts)"
echo "    notifications received during this drill:"
kubectl -n monitoring logs deploy/alert-webhook --since-time="$SINCE" | sed 's/^/      /'

echo
if [[ $FAILED == 0 ]]; then echo "DRILL 3 PASSED   finished $(ts)"; else echo "DRILL 3 HAD FAILURES   finished $(ts)"; exit 1; fi
