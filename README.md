# konforme-infrastructure

Terraform for Konforme on AWS (`eu-west-1`), serverless:

```
app.konforme.io ──► CloudFront ──► S3 (React build)

api.konforme.io ──► API Gateway (HTTP) ──► Lambda konforme-api ──┬──► DynamoDB table "konforme"
                                              │ async invoke      ├──► S3 (evidence, reports)
EventBridge Scheduler (4 daily jobs) ──► Lambda konforme-worker ──┴──► customer AWS/Azure APIs, Resend
CI after each deploy ──────────────────► Lambda konforme-migrate (seeds reference data)
```

All three Lambdas run the same container image (`konforme-backend/Dockerfile.lambda`), with different handlers.
No VPC is involved: Lambda reaches DynamoDB and the internet directly.

| File | What |
|---|---|
| `dynamodb.tf` | The single DynamoDB table + indexes (key layout: `konforme-backend/store.py`) |
| `lambda.tf` | Lambda functions, API Gateway + `api.` domain, daily schedules |
| `frontend.tf` | S3 + CloudFront + `app.` certificate and security headers |
| `github_oidc.tf` | IAM roles GitHub Actions assumes (no stored AWS keys) |
| `ec2.tf`, `vpc.tf`, `security.tf`, `ssm.tf`, EC2 parts of `iam.tf` | **Old stack — delete in Phase 3** |

## Rough monthly cost (low traffic)

| Item | ~USD |
|---|---|
| DynamoDB (on-demand reads/writes + storage, point-in-time recovery) | 1–5 |
| Lambda, API Gateway, CloudFront, S3, EventBridge | under 5 at current scale |

---

## Migration runbook (EC2 → Lambda)

The new stack is built **next to** EC2. Nothing user-facing changes until Phase 2 step 3.

### Prerequisites

- Working AWS credentials locally (`aws sts get-caller-identity` must succeed).
- `terraform.tfvars` with the existing values (see `terraform.tfvars.example`) plus the new ones:
  `lambda_image_tag`, `resend_api_key` (otherwise no emails are sent).
- Docker on your machine (to push the first image).

### Phase 1: build the serverless stack

```bash
# 1. Push the first Lambda image (CI pushes all later ones)
REPO=$(cd terraform && terraform output -raw ecr_repository_url)
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin "${REPO%%/*}"
cd ../Konforme-project            # build context is the repo root
docker build --platform linux/amd64 --provenance=false -f konforme-backend/Dockerfile.lambda -t "$REPO:bootstrap-1" .
docker push "$REPO:bootstrap-1"

# 2. Create everything (lambda_image_tag = "bootstrap-1" in tfvars). Takes ~10-15 min (CloudFront).
cd terraform && terraform init && terraform plan && terraform apply

# 3. Check the API can reach DynamoDB (an empty table is fine)
curl "$(terraform output -raw api_gateway_url)/health"      # → "database":"connected"
```

Then set up GitHub (values from `terraform output`) and let CI deploy the frontend to S3 once:

| Repo | Variables (Settings → Secrets and variables → Actions → Variables) |
|---|---|
| `Konforme-project-` | `AWS_ROLE_ARN` = `github_role_arns.backend` |
| `konforme-frontend` | `AWS_ROLE_ARN` = `github_role_arns.frontend`, `FRONTEND_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `VITE_API_URL=https://api.konforme.io`, `VITE_EMAIL_ENABLED` |
| `konforme-infrastructure` | Create environment **production** with yourself as required reviewer. Variables: `AWS_ROLE_ARN` = `github_role_arns.infra`, `TF_VAR_KONFORME_AWS_ACCOUNT_ID`, `TF_VAR_SSH_KEY_NAME`, `TF_VAR_ADMIN_CIDR_BLOCKS`, `TF_VAR_LAMBDA_IMAGE_TAG`, `TF_VAR_CUTOVER_TO_LAMBDA`, `TF_VAR_BUDGET_ALERT_EMAIL`. Secrets: `TF_VAR_SECRET_KEY`, `TF_VAR_ENCRYPTION_KEY`, `TF_VAR_POSTGRES_PASSWORD`, `TF_VAR_RESEND_API_KEY` |

`TF_VAR_SECRET_KEY`, `TF_VAR_ENCRYPTION_KEY` and `TF_VAR_POSTGRES_PASSWORD` **must be the values already in use**.
`ENCRYPTION_KEY` decrypts the stored customer cloud credentials; a new key makes all of them unreadable.
(`TF_VAR_POSTGRES_PASSWORD` is only needed until the EC2 stack is removed.)

### Phase 2: move the data and cut over (~15 min downtime)

```bash
IMAGE="$(terraform output -raw ecr_repository_url):bootstrap-1"
scp ../scripts/migrate-ec2-to-dynamodb.sh ec2-user@<EC2_IP>:

# 1a. Rehearsal: reads and converts every row, writes nothing, site stays up
ssh ec2-user@<EC2_IP> ./migrate-ec2-to-dynamodb.sh "$IMAGE" --dry-run

# 1b. The real copy. Stops the EC2 backend, backs Postgres up to S3, copies every table into DynamoDB,
#     compares row counts and re-verifies every account's audit hash chain. Fails loudly on any mismatch.
ssh ec2-user@<EC2_IP> ./migrate-ec2-to-dynamodb.sh "$IMAGE"

# 2. Refresh reference data (base controls, question mappings)
aws lambda invoke --function-name konforme-migrate --cli-read-timeout 310 /dev/stdout

# 3. Switch DNS to API Gateway/CloudFront and turn on the daily jobs
terraform apply -var cutover_to_lambda=true          # then set it permanently in tfvars / GitHub vars

# 4. Verify: log in at https://app.konforme.io, run a scan, upload + download evidence, generate a report
```

**Rollback before step 3:** `ssh ec2-user@<EC2_IP> 'cd /opt/konforme && docker compose start backend'`.
**Rollback after step 3:** `terraform apply -var cutover_to_lambda=false` and restart the EC2 backend.
Anything written to DynamoDB after cutover would need copying back by hand.

### Phase 3: remove EC2 (after about a week of stable running)

1. Snapshot the `konforme-postgres-data` EBS volume (it has `prevent_destroy`; remove that line to delete it).
2. Delete `ec2.tf`, `vpc.tf`, `security.tf`, `ssm.tf`, `templates/`, `scripts/deploy.sh` and
   `scripts/migrate-ec2-to-dynamodb.sh`; the EC2 role and GitLab user in `iam.tf`; `aws_iam_role_policy.ec2_dynamodb_migration`
   in `dynamodb.tf`; the EC2 outputs; the nginx/postgres log groups; the EC2 variables (`instance_type`,
   `ssh_key_name`, `admin_cidr_blocks`, volume sizes, `postgres_password`).
3. In `dns.tf`, drop the `cutover_to_lambda` conditionals and keep only the alias records.
4. `terraform apply`, then delete the old `konforme-gitlab-ci` access keys if any remain.

## Operating notes

- **Logs:** CloudWatch `/aws/lambda/konforme-{api,worker,migrate}` and `/aws/apigateway/konforme-api`.
- **First request after idle** takes a few seconds while the Lambda cold-starts.
- **Backups:** DynamoDB point-in-time recovery keeps 35 days; restore with
  `aws dynamodb restore-table-to-point-in-time` (it restores into a new table).
- **Data model:** everything is in one table; read `konforme-backend/store.py` before adding a new model or query pattern.
- **Outbound IP:** Lambdas outside a VPC have no fixed outbound IP, so customers cannot allowlist Konforme by IP.
