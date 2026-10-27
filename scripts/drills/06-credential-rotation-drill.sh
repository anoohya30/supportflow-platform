#!/bin/bash
# Drill 6 - Credential rotation: rotate the staging database password,
# refresh the API, prove the NEW credential works and the OLD one is
# rejected. Neither value is ever printed (only an 8-character fingerprint).
# Run ON THE HOST:  sudo ./scripts/drills/06-credential-rotation-drill.sh
set -uo pipefail
source "$(dirname "$0")/_common.sh"
NS=staging
fp() { printf '%s' "$1" | sha256sum | cut -c1-8; }
TRY_URL='
import sys, psycopg
url = sys.stdin.read().strip().replace("postgresql+psycopg://", "postgresql://")
try:
    psycopg.connect(url, connect_timeout=5).close()
    print("ACCEPTED")
except psycopg.OperationalError as e:
    msg = str(e).strip().splitlines()[-1]
    print("REJECTED (" + msg[msg.find("password authentication"):][:60] + ")")
'
try_url() { printf '%s' "$1" | kubectl -n $NS exec -i deploy/supportflow-api -c api -- python -c "$TRY_URL"; }

echo "Drill 6: database credential rotation   started $(ts)"
OLD_URL=$(kubectl -n $NS get secret supportflow-db -o jsonpath='{.data.database-url}' | base64 -d)
OLD_PW=$(kubectl -n $NS get secret supportflow-db -o jsonpath='{.data.postgres-password}' | base64 -d)
NEW_PW=$(openssl rand -hex 24)
NEW_URL="${OLD_URL/$OLD_PW/$NEW_PW}"
echo "    old password fingerprint: $(fp "$OLD_PW")   new password fingerprint: $(fp "$NEW_PW")"

step "baseline: the old credential works"
echo "    old credential: $(try_url "$OLD_URL")"

step "rotate: change the password in PostgreSQL (sent on stdin, never on a command line)"
printf "ALTER USER supportflow WITH PASSWORD '%s';\n" "$NEW_PW" | psql_in $NS -d supportflow -q

step "update the Kubernetes Secret and refresh the API"
printf 'postgres-password=%s\ndatabase-url=%s\n' "$NEW_PW" "$NEW_URL" \
  | kubectl -n $NS create secret generic supportflow-db --from-env-file=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f - 2>/dev/null
kubectl -n $NS rollout restart deploy/supportflow-api >/dev/null
kubectl -n $NS rollout status deploy/supportflow-api --timeout=180s

step "verify"
R_OLD=$(try_url "$OLD_URL"); R_NEW=$(try_url "$NEW_URL")
echo "    old credential: $R_OLD"
echo "    new credential: $R_NEW"
[[ "$R_OLD" == REJECTED* ]] && pass "old credential no longer works" || fail "old credential still accepted"
[[ "$R_NEW" == ACCEPTED ]] && pass "new credential works" || fail "new credential rejected"
echo "    secret fingerprint now: $(fp "$(kubectl -n $NS get secret supportflow-db -o jsonpath='{.data.postgres-password}' | base64 -d)")"
kubectl -n $NS get pods -l app.kubernetes.io/component=api
echo "    tickets: $(ticket_count $NS)"
unset OLD_URL OLD_PW NEW_PW NEW_URL
printf '%s env=%s event=db-password-rotated old_rejected=%s new_accepted=%s\n' "$(ts)" "$NS" \
  "$([[ "$R_OLD" == REJECTED* ]] && echo yes || echo no)" "$([[ "$R_NEW" == ACCEPTED ]] && echo yes || echo no)" \
  | tee -a /var/log/supportflow/rotations.log

echo
if [[ $FAILED == 0 ]]; then echo "DRILL 6 PASSED   finished $(ts)"; else echo "DRILL 6 HAD FAILURES   finished $(ts)"; exit 1; fi
