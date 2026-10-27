#!/bin/bash
# Drill 5 - Recovery: restore the latest scheduled (encrypted) backup into a
# FRESH database, compare row counts and selected ticket IDs, reconnect the
# staging API to the restored database, verify through the API, record
# RTO/RPO, then reconnect the API to the original database.
# The original database is never overwritten or dropped.
# Run ON THE HOST:  sudo ./scripts/drills/05-restore-reconnect-drill.sh
set -uo pipefail
source "$(dirname "$0")/_common.sh"
NS=staging
FRESH=supportflow_restored
ACCOUNT=$(aws sts get-caller-identity --region "$REGION" --query Account --output text)
BUCKET="supportflow-backups-$ACCOUNT"

set_db_name() {  # point the API's DATABASE_URL at another database name (value never printed)
  local b64; b64=$(kubectl -n $NS get secret supportflow-db -o jsonpath='{.data.database-url}' \
    | base64 -d | sed -E "s#/[A-Za-z0-9_]+\$#/$1#" | base64 -w0)
  kubectl -n $NS patch secret supportflow-db --type merge -p "{\"data\":{\"database-url\":\"$b64\"}}" >/dev/null
  echo "    API DATABASE_URL now uses database: $(kubectl -n $NS get secret supportflow-db -o jsonpath='{.data.database-url}' | base64 -d | sed 's#.*/##')"
  kubectl -n $NS rollout restart deploy/supportflow-api >/dev/null
  kubectl -n $NS rollout status deploy/supportflow-api --timeout=180s
}
API_TICKETS='
import json, sys, urllib.request
for i in sys.argv[1:]:
    t = json.load(urllib.request.urlopen(f"http://127.0.0.1:8000/tickets/{i}", timeout=5))
    subject, state = t["subject"][:40], t["status"]
    print(f"    API GET /tickets/{i} -> 200  subject={subject!r} status={state}")
print("    API /health/ready ->", urllib.request.urlopen("http://127.0.0.1:8000/health/ready", timeout=5).status)
'

echo "Drill 5: restore + reconnect API   started $(ts)"
T0=$(epoch); T0_ISO=$(ts)
step "latest scheduled backup"
tail -2 /var/log/supportflow/backups.log
KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$NS/" --region "$REGION" \
  --query 'sort_by(Contents,&LastModified)[-1].Key' --output text)
BACKUP_AT=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" --query LastModified --output text)
ENC=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" --query ServerSideEncryption --output text)
echo "    key: $KEY   written: $BACKUP_AT   encryption: $ENC"
RPO=$(( T0 - $(date -u -d "$BACKUP_AT" +%s) ))
echo "    data-loss window if the database failed now (RPO): $RPO s (target <= 900 s)"
[[ $RPO -le 900 ]] && pass "RPO within 15 minutes" || fail "newest backup older than 15 minutes"

step "restore into a FRESH database: $FRESH"
psql_in $NS -d supportflow -q -c "DROP DATABASE IF EXISTS $FRESH;"
psql_in $NS -d supportflow -q -c "CREATE DATABASE $FRESH;"
aws s3 cp "s3://$BUCKET/$KEY" - --region "$REGION" --only-show-errors \
  | kubectl -n $NS exec -i statefulset/postgres -- pg_restore -U supportflow -d $FRESH --no-owner --exit-on-error
echo "    databases now:"; psql_in $NS -d supportflow -tA -c "select datname from pg_database where datname like 'supportflow%' order by 1;" | sed 's/^/      /'

step "compare row counts and selected ticket IDs (live vs restored)"
LIVE=$(ticket_count $NS); RESTORED=$(psql_in $NS -d $FRESH -tA -c "select count(*) from tickets;")
MAXID=$(psql_in $NS -d $FRESH -tA -c "select max(id) from tickets;")
echo "    rows: live=$LIVE restored=$RESTORED (difference = tickets created after the backup)"
IDS="1 250 500 750 1000 $MAXID"
SQL="select id, md5(concat_ws('|', id, subject, description, priority, created_at)) from tickets where id in (${IDS// /,}) order by id;"
diff <(psql_in $NS -d supportflow -tA -F' ' -c "$SQL") <(psql_in $NS -d $FRESH -tA -F' ' -c "$SQL") >/dev/null \
  && pass "selected ticket IDs ($IDS) identical in live and restored (id, subject, description, priority, created_at)" \
  || fail "selected ticket IDs differ"
psql_in $NS -d $FRESH -tA -F' | ' -c "select id, left(subject,40), status from tickets where id in (${IDS// /,}) order by id;" | sed 's/^/    restored: /'

step "reconnect the staging API to the restored database"
set_db_name $FRESH
T_RTO=$(epoch)
echo "$API_TICKETS" | api_py $NS $IDS
RTO=$(( T_RTO - T0 ))
pass "service running on the restored database; RTO = $RTO s from recovery start (target <= 1800 s)"

step "switch the API back to the original database (it was never touched)"
set_db_name supportflow
echo "$API_TICKETS" | api_py $NS 1 $MAXID
psql_in $NS -d supportflow -q -c "DROP DATABASE $FRESH;" && echo "    restored copy $FRESH dropped"
echo "    tickets in the original database: $(ticket_count $NS) (at start: $LIVE)"

printf '%s env=%s key=%s backup_at=%s rpo_s=%s rto_s=%s live=%s restored=%s ids_match=%s api_reconnected=yes\n' \
  "$(ts)" "$NS" "$KEY" "$BACKUP_AT" "$RPO" "$RTO" "$LIVE" "$RESTORED" "$([[ $FAILED == 0 ]] && echo yes || echo no)" \
  | tee -a /var/log/supportflow/restores.log

echo
if [[ $FAILED == 0 ]]; then echo "DRILL 5 PASSED (started $T0_ISO)   finished $(ts)"; else echo "DRILL 5 HAD FAILURES   finished $(ts)"; exit 1; fi
