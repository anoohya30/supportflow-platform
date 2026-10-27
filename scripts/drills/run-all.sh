#!/bin/bash
# Run all failure drills one after another (about 30 minutes), save each
# output to /var/log/supportflow/drills/, mask the AWS account number, and
# copy the logs to the encrypted backups bucket under evidence/ so they can
# be downloaded on the laptop. Run ON THE HOST:
#   sudo ./scripts/drills/run-all.sh            # all drills
#   sudo ./scripts/drills/run-all.sh 04 05      # only some
set -uo pipefail
cd "$(dirname "$0")" || exit 1
REGION="eu-west-2"
OUT=/var/log/supportflow/drills
mkdir -p "$OUT"
ACCOUNT=$(aws sts get-caller-identity --region "$REGION" --query Account --output text)
SELECT=("$@")
[[ ${#SELECT[@]} -eq 0 ]] && SELECT=(01 02 03 04 05 06)
for n in "${SELECT[@]}"; do
  script=$(ls "$n"-*.sh)
  log="$OUT/${script%.sh}.log"
  echo "################ $script ################"
  bash "$script" 2>&1 | sed -E 's/[0-9]{12}/<account>/g' | tee "$log"
  aws s3 cp "$log" "s3://supportflow-backups-$ACCOUNT/evidence/$(basename "$log")" \
    --region "$REGION" --sse AES256 --only-show-errors
done
echo
grep -h "^DRILL" "$OUT"/*.log
