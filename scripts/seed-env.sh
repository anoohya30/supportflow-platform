#!/bin/bash
# Insert 1,000 synthetic tickets into one environment's database.
# Run ON THE HOST:  sudo ./scripts/seed-env.sh staging
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
ENV_NAME="${1:?Usage: $0 <staging|production-lab>}"

kubectl -n "$ENV_NAME" exec statefulset/postgres -- psql -U supportflow -d supportflow -v ON_ERROR_STOP=1 -c "
INSERT INTO tickets (subject, description, priority, status)
SELECT 'Synthetic ticket #' || g,
       'Synthetic ticket generated for testing. No real customer data.',
       (ARRAY['low','normal','high'])[1 + g % 3],
       (ARRAY['open','in_progress','closed'])[1 + (g / 3) % 3]
FROM generate_series(1, 1000) AS g;"

kubectl -n "$ENV_NAME" exec statefulset/postgres -- psql -U supportflow -d supportflow -t -c "SELECT count(*) AS tickets FROM tickets;"
