# Evidence: AWS platform provisioned (Day 7, 2026-10-16)

Region: eu-west-2 (London). Account details intentionally omitted.

## Terraform
- Bootstrap (state bucket): 6 resources. Versioning `Enabled`, public access block `True True True True`, encryption `AES256`.
- Platform plan: `Plan: 25 to add, 0 to change, 0 to destroy.`
- Platform apply: `Apply complete! Resources: 25 added, 0 changed, 0 destroyed.`

## Host
- Instance `i-0945ff184adefa42c`: `running`, type `m7i-flex.large` (AWS Free plan, D-015), IMDSv2 `required`.
- Public IP 18.135.157.38. Only port 80 open; no SSH.
- Session Manager: `PingStatus = Online`; logged in without SSH keys.
- Bootstrap marker: `READY`; log ends `SupportFlow host bootstrap complete`.

## Kubernetes
- `kubectl get nodes`: 1 node `Ready`, `v1.36.5+k3s1`.
- Namespaces `staging` and `production-lab`: `Active`.
- ECR pull secret `ecr-pull` present (refreshed every 6h by systemd timer).
- Helm `v3.22.0`.
- `curl http://staging.18-135-157-38.sslip.io` -> `404` (Traefik ingress answering; app not yet deployed).

## CI to AWS
- Repository variable `AWS_ROLE_ARN` set (GitHub OIDC; no AWS keys stored in GitHub).
