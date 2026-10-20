# Architecture

Lab context: one AWS account, region eu-west-2 (London), AWS Free plan. Engineering
assessment / portfolio project with synthetic data only.

```
                         TRUST BOUNDARY: GitHub
  developer --PR--> GitHub repo --4 required checks--> merge to main
                         |  GitHub Actions on main: build image ONCE, Trivy, SBOM
                         |  OIDC token (sub = repo:<owner>@<id>/<repo>@<id>:ref:refs/heads/main)
  ======================= v ======================= TRUST BOUNDARY: AWS account
                    STS AssumeRoleWithWebIdentity -> role: push to ECR only
                         v
                    Amazon ECR (immutable tags, scan on push)  -- image@sha256 --+
                                                                                 |
  operator laptop --Session Manager (IAM auth, logged, no SSH)--+                |
                                                                v                v
   +--------------------------- VPC 10.20.0.0/16, public subnet ----------------------+
   |  EC2 m7i-flex.large, Ubuntu 24.04, k3s, IMDSv2 (hop limit 1), encrypted gp3 disk  |
   |  Security group: inbound TCP 80 only                                              |
   |                                                                                   |
   |   namespace staging          namespace production-lab      namespace monitoring   |
   |   Traefik ingress -> 2 x API   Traefik ingress -> 2 x API    Prometheus            |
   |        -> PostgreSQL (PVC)        -> PostgreSQL (PVC)        Alertmanager, Grafana |
   |   NetworkPolicy: API <- kube-system (Traefik), node, monitoring                    |
   |   NetworkPolicy: PostgreSQL <- SupportFlow pods in the same namespace only         |
   |                                                                                   |
   |   systemd timers: ECR pull-secret refresh (6 h), database backups (15 min)        |
   +-----------------------------------------------------------------------------------+
         | host IAM role: ECR pull (app repo only), S3 put/get (backups bucket only)
         v
   S3 backups bucket (AES256, versioned, public access blocked, lifecycle)
   S3 Terraform state bucket (AES256, versioned, TLS-only policy, lock file)

  users --HTTP :80--> staging.<ip>.sslip.io / prod.<ip>.sslip.io
  operator --SSM port forwarding--> Grafana 30300, Prometheus 30090, Alertmanager 30093 (not public)
```

## Data paths
- **Request:** user -> port 80 -> Traefik -> API pod -> PostgreSQL in the same namespace.
- **Release:** PR -> checks -> merge -> CI builds once -> ECR (digest) -> `deploy-env.sh staging <digest>`
  -> Helm (migration Job first, then rolling update) -> same digest to production-lab.
- **Metrics:** Prometheus scrapes each API pod's `/metrics` (allowed by NetworkPolicy) and
  kube-state-metrics; Grafana reads Prometheus; Alertmanager receives fired alerts.
- **Backups:** host timer -> `pg_dump` inside the PostgreSQL pod -> stream -> S3 (host role).

## Trust boundaries and controls
| Boundary | Control |
|---|---|
| GitHub -> AWS | OIDC, role trusts only `main` of this repository by immutable IDs; ECR push only |
| Internet -> host | Security group allows TCP 80 only; no SSH; admin UIs reachable only via SSM tunnel |
| Operator -> host | Session Manager with IAM authentication and session logging |
| Pod -> AWS credentials | IMDSv2 required, hop limit 1 (pods cannot reach the host role) |
| Pod -> pod | NetworkPolicies on API and PostgreSQL |
| Secrets | DB passwords and Grafana password generated randomly, stored only in Kubernetes Secrets |

## Production limitations (accepted for the lab)
Single host and single AZ; HTTP only (no TLS); no external secrets manager; no GitOps
reconciliation or reviewer-enforced promotion gate; monitoring data not persistent; backups
in the same region. See `docs/security-exceptions.md` and `docs/decisions.md`.
