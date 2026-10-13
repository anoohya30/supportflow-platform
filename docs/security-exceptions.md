# Security Exceptions

Findings from the infrastructure security scan (checkov) that are **accepted
for this lab**. They are skipped in `.checkov.yaml`; any *new* finding fails
CI. Owner for all: Anoohya Bhairavabatla. **Expiry: 2026-11-13** (one month,
or at teardown, whichever is first). A real service must resolve each one.

| Check | Resource | Risk | Why accepted (lab) | Fix for a real service |
|---|---|---|---|---|
| CKV_AWS_260 | Port 80 open to internet | Traffic is unencrypted HTTP | It's the intended app entry point; no domain/TLS in scope | HTTPS with a real domain + cert-manager, or an ALB with ACM |
| CKV_AWS_130 | Public IP on subnet | Host directly reachable | No NAT gateway (cost) | Private subnets + NAT/ALB |
| CKV2_AWS_11 | No VPC flow logs | Less network forensics | Cost | Enable flow logs to CloudWatch/S3 |
| CKV_AWS_126 | No EC2 detailed monitoring | 5-min metrics only | Cost | Enable, plus Prometheus |
| CKV_AWS_136, CKV_AWS_145 | AES256 instead of KMS | No key-level access control | Simpler, no KMS cost | Customer-managed KMS keys |
| CKV_AWS_18 | No S3 access logging | Less audit trail | Cost | Access logs or CloudTrail data events |
| CKV_AWS_144 | No cross-region replication | Region loss = data loss | Cost | Replicate backups to a second region |
| CKV2_AWS_62 | No S3 event notifications | No alert on changes | Not needed for lab | EventBridge notifications |
| CKV_AWS_394 | AZ list not pinned | Placement could change | Single subnet, single AZ | Pin AZ IDs |
| CKV_K8S_35 | DB URL as env var from Secret | Visible to processes in pod | App reads env vars | Mount as file / external secrets operator |
| CKV_K8S_43, CKV_K8S_15 | Postgres image by tag | Tag could change | App image IS digest-pinned | Pin postgres by digest |
| CKV_K8S_22, CKV_K8S_40 | Postgres writable FS, UID 70 | Default image behaviour | Database must write; official image user | Managed PostgreSQL (RDS) |
| CKV_K8S_21, CKV2_K8S_6 | "default namespace", "no NetworkPolicy" | — | **False positives**: deployed into staging/production-lab; policy is in the same file | — |

Also accepted (not scanner findings):

| Item | Risk | Note |
|---|---|---|
| IAM user with AdministratorAccess + access key on laptop | Key theft = full account access | Short lab only; key deleted at teardown (runbook 6) |
| Host IAM role shared by host processes | Not per-pod IAM | IMDS hop limit 1 blocks pods from reaching the role |
| DB password in Kubernetes Secret (not AWS Secrets Manager) | Secrets only base64 in etcd | Generated randomly at deploy, never in Git; Secrets Manager not completed |
