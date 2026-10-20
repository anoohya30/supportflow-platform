#!/bin/bash
# Captioned walkthrough for the assessment recording (no narration needed).
# Run on the LAPTOP from the repo folder, with the lab host running:
#
#   source .venv/bin/activate
#   ./scripts/demo.sh
#
# Each section prints a caption, runs the commands, then waits for Enter.
# Host commands run through AWS Systems Manager (no SSH). Any 12-digit
# AWS account number in the output is masked automatically.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BOLD=$(tput bold 2>/dev/null || true); CYAN=$(tput setaf 6 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true); RESET=$(tput sgr0 2>/dev/null || true)
mask() { sed -E 's/[0-9]{12}/<account>/g'; }

INSTANCE_ID=$(terraform -chdir=infra/platform output -raw instance_id)
STAGING=$(terraform -chdir=infra/platform output -raw staging_url)
PROD=$(terraform -chdir=infra/platform output -raw production_lab_url)
STEP=0

say() {   # big caption
  STEP=$((STEP + 1)); clear
  echo "${CYAN}${BOLD}=================================================================="
  echo "  $STEP. $1"
  echo "==================================================================${RESET}"
  shift
  for line in "$@"; do echo "  $line"; done
  echo
}
run() { echo "${GREEN}\$ $*${RESET}"; eval "$*" 2>&1 | mask; echo; }
pause() { read -r -p "${BOLD}--- press Enter to continue ---${RESET}" _; }
browser() { echo "${BOLD}>>> BROWSER: $*${RESET}"; echo; }

remote() {   # run a command on the lab host through SSM and print its output
  echo "${GREEN}[host]\$ $1${RESET}"
  local cmd="export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; cd /opt/supportflow; $1"
  local params cid
  params=$(python3 -c 'import json,sys; print(json.dumps({"commands":[sys.argv[1]]}))' "$cmd")
  cid=$(aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
        --parameters "$params" --query Command.CommandId --output text)
  aws ssm wait command-executed --command-id "$cid" --instance-id "$INSTANCE_ID" 2>/dev/null || true
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$INSTANCE_ID" \
      --query '[StandardOutputContent,StandardErrorContent]' --output text | mask
  echo
}

say "SupportFlow - DevOps assessment walkthrough" \
  "Engineering assessment / portfolio project (SkillAnthem DEVOPS 01). Synthetic data only." \
  "A small ticket API, and the platform that builds, deploys, monitors and recovers it on AWS." \
  "" \
  "This recording shows: architecture, release flow, infrastructure as code, the live" \
  "environments, monitoring and alerts, self-healing, backups and restore, security," \
  "measured results, cost, and what is not completed."
browser "open docs/presentation.md on GitHub and scroll through it (problem, architecture, trust boundaries)"
pause

say "Release flow: every change goes through a pull request" \
  "4 required checks: lint + migrations + 19 tests, secret scan, IaC checks, image build + vulnerability scan + SBOM." \
  "On main, CI builds the image ONCE and pushes it to ECR via GitHub OIDC (no AWS keys stored in GitHub)."
run "gh pr list --state merged --limit 12"
run "gh run list --branch main --limit 5"
run "gh variable list --json name --jq '.[].name'"
browser "show one closed PR with its 4 green checks, then Actions -> a main run -> 'Push the tested image to ECR'"
pause

say "Infrastructure as code: Terraform" \
  "infra/bootstrap = encrypted, versioned S3 state bucket. infra/platform = VPC, EC2 k3s host, ECR, IAM/OIDC, S3 backups (25 resources)." \
  "A plan against the real account shows no drift between the code and AWS."
run "terraform -chdir=infra/platform plan -no-color | tail -3"
run "aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].[State.Name,InstanceType,MetadataOptions.HttpTokens]' --output text"
pause

say "Build once, promote the same artifact" \
  "staging and production-lab run the exact same image digest; nothing is rebuilt per environment." \
  "Helm history shows the bad release (failed) and the rollback to the healthy revision."
remote "for ns in staging production-lab; do echo \"\$ns: \$(kubectl -n \$ns get deploy supportflow-api -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's|.*@||')\"; done"
remote "helm -n staging history supportflow --max 6"
remote "tail -3 /var/log/supportflow/releases.log"
pause

say "The live environments" \
  "Both environments answer on the internet through Traefik (only port 80 is open)." \
  "The smoke test calls every endpoint of production-lab."
run "curl -s $STAGING/version; echo"
run "curl -s $PROD/version; echo"
run "python scripts/smoke_test.py --base-url $PROD"
browser "open $STAGING/docs (the API's Swagger page)"
pause

say "Monitoring under load" \
  "Prometheus scrapes /metrics from all 4 API pods; Grafana shows the SupportFlow dashboard." \
  "Now a 30-second k6 burst at 20 requests/second against staging. Watch the Grafana dashboard." \
  "(The full 10-minute test passed: 12,001 requests, p95 28.21 ms, 0% server errors.)"
browser "switch to Grafana (http://localhost:3000/d/supportflow) while the test runs, then come back"
run "docker run --rm -i -u \"\$(id -u):\$(id -g)\" -e BASE_URL=$STAGING -e DURATION=30s grafana/k6:1.8.1 run --no-color --quiet - < load-tests/k6-tickets.js | sed -n '/THRESHOLDS/,/TOTAL RESULTS/p'"
pause

say "Alert rules" \
  "Five SupportFlow alert rules. All are inactive now (healthy)." \
  "In the alert drill, scaling staging to 0 fired SupportFlowNoAvailablePods within 2 minutes."
remote "NODE_IP=\$(hostname -I | awk '{print \$1}'); curl -s http://\$NODE_IP:30090/api/v1/rules | jq -r '.data.groups[] | select(.name|startswith(\"supportflow\")) | .rules[] | \"\\(.name)  \\(.state)\"'"
pause

say "Self-healing: kill an API pod" \
  "Kubernetes replaces the pod; the second replica keeps serving, so users see no errors."
remote "POD=\$(kubectl -n staging get pods -l app.kubernetes.io/name=supportflow --field-selector=status.phase=Running -o name | head -1); echo deleting \$POD; kubectl -n staging delete \$POD; sleep 20; kubectl -n staging get pods"
run "for i in 1 2 3 4 5; do curl -s -o /dev/null -w '%{http_code} ' $STAGING/health/ready; sleep 1; done; echo"
pause

say "Backups every 15 minutes, and a verified restore" \
  "pg_dump to the encrypted S3 bucket using the host's IAM role (RPO 15 min)." \
  "The restore drill restores the newest backup into a FRESH database and compares row counts." \
  "The live database is never touched."
remote "systemctl list-timers supportflow-backup.timer --no-pager | head -2"
remote "tail -4 /var/log/supportflow/backups.log"
remote "./scripts/restore-db.sh staging"
pause

say "Security" \
  "Only port 80 is open; no SSH (access via Session Manager); IMDSv2 required; non-root container;" \
  "NetworkPolicies; encrypted buckets; no secrets in Git (gitleaks on every PR)."
run "aws ec2 describe-security-groups --filters Name=tag:Project,Values=supportflow --query 'SecurityGroups[].IpPermissions[].[IpProtocol,FromPort,ToPort]' --output text"
remote "kubectl -n staging get networkpolicy"
pause

say "Cost" \
  "AWS Free plan (credits, the card cannot be charged). Host stopped between work sessions." \
  "Remaining credit (started at USD 119.18):"
run "aws freetier get-account-plan-state --region us-east-1 --query accountPlanRemainingCredits.amount --output text"
pause

say "Results and remaining limitations" \
  "PASSED: load test (p95 28.21 ms, 0% 5xx), rollback < 3 min, restore ~5 s, RPO 15 min," \
  "        alert drill, pod and database kill drills, same digest in both environments." \
  "NOT COMPLETED: reviewer-enforced promotion gate, Argo CD (GitOps reconciliation)." \
  "PARTIAL: alert notifications, drift check is manual, HTTPS (HTTP only), DB password rotation." \
  "" \
  "Full requirement-to-evidence matrix: docs/acceptance-evidence.md. Thank you."
browser "open docs/acceptance-evidence.md on GitHub and scroll through it"
pause
echo "End of walkthrough."
