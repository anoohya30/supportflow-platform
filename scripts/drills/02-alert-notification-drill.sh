#!/bin/bash
# Drill 2 - Alert notification: no ready API replicas in staging for 1 minute
# -> FIRING notification at the local webhook collector, then recovery ->
# RESOLVED notification. Run ON THE HOST:
#   sudo ./scripts/drills/02-alert-notification-drill.sh
set -uo pipefail
source "$(dirname "$0")/_common.sh"
NS=staging

echo "Drill 2: alert notifications (SupportFlowNoAvailablePods)   started $(ts)"
kubectl -n monitoring get deploy alert-webhook
step "baseline"
kubectl -n $NS get deploy supportflow-api
BEFORE=$(ticket_count $NS); echo "    tickets: $BEFORE"

SINCE=$(ts)
step "inject: scale staging API to 0 replicas"
T_INJECT=$(epoch)
kubectl -n $NS scale deploy/supportflow-api --replicas=0

step "waiting for the FIRING notification (rule: < 1 available replica for 1m)"
if FIRING_LINE=$(wait_notification "status=FIRING alert=SupportFlowNoAvailablePods namespace=$NS" "$SINCE" 420); then
  echo "$FIRING_LINE"
  STARTS=$(echo "$FIRING_LINE" | tail -1 | sed -E 's/.*startsAt=([^ ]+).*/\1/')
  pass "FIRING notification received $(( $(epoch) - T_INJECT )) s after the injection (alert startsAt=$STARTS)"
else
  fail "no FIRING notification within 7 minutes"
fi

step "mitigate: scale staging API back to 2 replicas"
T_FIX=$(epoch)
kubectl -n $NS scale deploy/supportflow-api --replicas=2
kubectl -n $NS rollout status deploy/supportflow-api --timeout=180s

step "waiting for the RESOLVED notification"
# Match the RESOLVED message of THIS alert (same startsAt), not an older one.
if wait_notification "status=RESOLVED alert=SupportFlowNoAvailablePods namespace=$NS .*startsAt=${STARTS:-none}" "$SINCE" 420; then
  pass "RESOLVED notification received $(( $(epoch) - T_FIX )) s after recovery"
else
  fail "no RESOLVED notification within 7 minutes"
fi

step "verify"
AFTER=$(ticket_count $NS); echo "    tickets: $AFTER (before: $BEFORE)"
[[ "$AFTER" -ge "$BEFORE" ]] && pass "no tickets lost" || fail "ticket count dropped"
echo "    all notifications received during this drill:"
kubectl -n monitoring logs deploy/alert-webhook --since-time="$SINCE" | sed 's/^/      /'

echo
if [[ $FAILED == 0 ]]; then echo "DRILL 2 PASSED   finished $(ts)"; else echo "DRILL 2 HAD FAILURES   finished $(ts)"; exit 1; fi
