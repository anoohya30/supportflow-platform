# Evidence: deploy to staging, promote to production-lab, rollback (Day 8, 2026-10-17)

Image (built once by CI on main, pushed via OIDC):
supportflow@sha256:f8048fab35bae9719a94e97bbccb8abaa4074cac59cb087fcf55a7695f06b0dc
(commit 77542d6c182512318d8226adafa36b4aa6a9b2b5, version 0.1.0). Account ID omitted.

## 1. Staging deploy (scripts/deploy-env.sh staging <image@digest>)
- DB secret created with a random password (stored only in Kubernetes).
- PostgreSQL ready -> migration Job Completed -> 2 API pods Running.
- Helm: STATUS deployed, REVISION 1.
- /version -> {"version":"0.1.0","commit":"77542d6c182512318d8226adafa36b4aa6a9b2b5"}
- Seed: INSERT 0 1000 (synthetic data only).
- /health/ready -> {"status":"ready","database":"reachable"}
- Smoke test from laptop against http://staging.18-135-157-38.sslip.io: 10/10 PASS, ALL CHECKS PASSED (total tickets 1001).

## 2. Promotion to production-lab (same digest, no rebuild)
- Separate database and password; migration Completed; 2 API pods Running; Helm deployed rev 1.
- Seed: INSERT 0 1000.
- Smoke test against http://prod.18-135-157-38.sslip.io: ALL CHECKS PASSED.

Digest actually running (kubectl get deploy ... -o jsonpath):

    staging:        sha256:f8048fab35bae9719a94e97bbccb8abaa4074cac59cb087fcf55a7695f06b0dc
    production-lab: sha256:f8048fab35bae9719a94e97bbccb8abaa4074cac59cb087fcf55a7695f06b0dc

Release log (/var/log/supportflow/releases.log, account masked):

    2026-10-17T13:27:08Z env=staging version=0.1.0 commit=77542d6c... image=<account>.dkr.ecr.eu-west-2.amazonaws.com/supportflow@sha256:f8048fab... operator=ssm-user
    2026-10-17T13:32:17Z env=production-lab version=0.1.0 commit=77542d6c... image=<account>.dkr.ecr.eu-west-2.amazonaws.com/supportflow@sha256:f8048fab... operator=ssm-user

## 3. Bad release + rollback (staging)
Deployed a non-existent image (all-zeros digest), migration hook disabled for the demo:
Error: UPGRADE FAILED: context deadline exceeded

helm -n staging history supportflow, after helm rollback supportflow 1:

    REVISION  STATUS      DESCRIPTION
    1         superseded  Install complete
    2         failed      Upgrade "supportflow" failed: context deadline exceeded
    3         deployed    Rollback to 1

- The running pods were 13 minutes old after the rollback: maxUnavailable 0 kept both original pods serving; the broken pod never became Ready.
- Uptime monitor from laptop (/health/ready every 2 s for 2 min): 60 x 200, no errors.
- Running image after rollback: sha256:f8048fab... (known good).
- Ticket count unchanged: 1001. Rollback changes the application only; migrations are additive.

## Not done here
- Reviewer-enforced approval gate for promotion (solo lab; manual promotion via Session Manager).
