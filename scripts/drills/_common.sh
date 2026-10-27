# shellcheck shell=bash disable=SC2034
# Shared helpers for the failure drills (sourced, not run).
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
REGION="eu-west-2"
ts() { date -u +%FT%TZ; }
epoch() { date -u +%s; }
step() { echo; echo "[$(ts)] ==> $*"; }
pass() { echo "[$(ts)] PASS: $*"; }
fail() { echo "[$(ts)] FAIL: $*"; FAILED=1; }
FAILED=0

# Run a small Python snippet inside one running API pod of a namespace.
api_py() { local ns="$1"; shift; kubectl -n "$ns" exec -i deploy/supportflow-api -c api -- python - "$@"; }

# Public HTTPS URL of an environment (sslip.io name of this host's public IP).
app_url() {
  local token ip prefix
  token=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
  ip=$(curl -sS -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/public-ipv4 | tr '.' '-')
  [[ "$1" == staging ]] && prefix=staging || prefix=prod
  echo "https://$prefix.$ip.sslip.io"
}

psql_in() { local ns="$1"; shift; kubectl -n "$ns" exec -i statefulset/postgres -- psql -U supportflow -v ON_ERROR_STOP=1 "$@"; }

ticket_count() { psql_in "$1" -d supportflow -tA -c "select count(*) from tickets;"; }

# Wait until the local webhook collector has received a notification line
# matching a pattern (since a given time). Prints the line(s) and returns 0.
wait_notification() {
  local pattern="$1" since="$2" timeout="${3:-420}" start; start=$(epoch)
  while (( $(epoch) - start < timeout )); do
    if kubectl -n monitoring logs deploy/alert-webhook --since-time="$since" 2>/dev/null | grep -E "$pattern"; then
      return 0
    fi
    sleep 10
  done
  return 1
}
