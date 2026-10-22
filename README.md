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
| `s3.tf` | Evidence and report buckets |

## Rough monthly cost (low traffic)

| Item | ~USD |
|---|---|
| DynamoDB (on-demand reads/writes + storage, point-in-time recovery) | 1–5 |
| Lambda, API Gateway, CloudFront, S3, EventBridge | under 5 at current scale |

---

## Setup runbook (Render + Netlify → AWS)

Today the backend runs on Render, the site on Netlify, and `konforme.io` DNS is Netlify DNS.
DNS stays on Netlify: Terraform prints the records to add there (`terraform output dns_records`).
Nothing user-facing changes until step 6.

### 1. Prerequisites (once)

- AWS login works: `aws sts get-caller-identity`.
- Docker running locally.
- `cp terraform/terraform.tfvars.example terraform/terraform.tfvars` and fill it in.
  `secret_key` and `encryption_key` **must be copied from Render** (backend service → Environment).
- Terraform state storage: `./scripts/init-state.sh`

### 2. Registry, certificates, first image

```bash
cd terraform && terraform init
terraform apply -target=aws_ecr_repository.backend -target=aws_acm_certificate.api -target=aws_acm_certificate.app
terraform output dns_records     # add every "certificate_checks" entry as a CNAME in Netlify DNS

REPO=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin "${REPO%%/*}"
cd ../../Konforme-project          # build context is the backend repo root
docker build --platform linux/amd64 --provenance=false -f konforme-backend/Dockerfile.lambda -t "$REPO:bootstrap-1" .
docker push "$REPO:bootstrap-1"
```

### 3. Everything else (~10-15 min, mostly CloudFront)

```bash
cd ../konforme-infrastructure/terraform
terraform plan
terraform apply                  # waits for the certificate checks from step 2 if DNS is still catching up
curl "$(terraform output -raw api_gateway_url)/health"      # → "database":"connected"
```

### 4. GitHub (values from `terraform output`)

| Repo | Variables (Settings → Secrets and variables → Actions) |
|---|---|
| `Konforme-project-` | `AWS_ROLE_ARN` = `github_role_arns.backend` |
| `konforme-frontend` | `AWS_ROLE_ARN` = `github_role_arns.frontend`, `FRONTEND_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `VITE_API_URL=https://api.konforme.io`, `VITE_EMAIL_ENABLED` |
| `konforme-infrastructure` | Environment **production** (you as reviewer). Variables: `AWS_ROLE_ARN` = `github_role_arns.infra`, `TF_VAR_LAMBDA_IMAGE_TAG`, `TF_VAR_CUTOVER_TO_LAMBDA`, `TF_VAR_BUDGET_ALERT_EMAIL`. Secrets: `TF_VAR_SECRET_KEY`, `TF_VAR_ENCRYPTION_KEY`, `TF_VAR_RESEND_API_KEY` |

Run the frontend workflow once so the site is in S3, and check it at `https://<cloudfront_domain>`.

### 5. Copy the data from Render (~15 min downtime)

```bash
export RENDER_DATABASE_URL='postgresql://...'    # Render → database → External Database URL
IMAGE="$(cd terraform && terraform output -raw ecr_repository_url):bootstrap-1"

./scripts/migrate-render-to-dynamodb.sh "$IMAGE" --dry-run   # rehearsal, writes nothing

# Suspend the Render backend service, then the real copy (backs Render up to a local file first,
# compares row counts and re-checks every audit hash chain; fails loudly on any mismatch)
./scripts/migrate-render-to-dynamodb.sh "$IMAGE"
aws lambda invoke --function-name konforme-migrate --cli-read-timeout 310 /dev/stdout
```

### 6. Switch over

1. In Netlify, remove `app.konforme.io` from the Netlify site's domains.
2. In Netlify DNS, set the two `at_cutover` records from `terraform output dns_records`
   (`api` replaces the CNAME to Render).
3. `terraform apply -var cutover_to_lambda=true` (daily jobs on), then set it in tfvars and the GitHub variable.
4. Check: log in at https://app.konforme.io, run a scan, upload + download evidence, generate a report.

**Rollback:** point the `api`/`app` records back to Render/Netlify and resume the Render service.
Anything written to DynamoDB after the switch would need copying back by hand.

After about a week of stable running, delete the Render service and database.

## Operating notes

- **Logs:** CloudWatch `/aws/lambda/konforme-{api,worker,migrate}` and `/aws/apigateway/konforme-api`.
- **First request after idle** takes a few seconds while the Lambda cold-starts.
- **Backups:** DynamoDB point-in-time recovery keeps 35 days; restore with
  `aws dynamodb restore-table-to-point-in-time` (it restores into a new table).
- **Data model:** everything is in one table; read `konforme-backend/store.py` before adding a new model or query pattern.
- **Outbound IP:** Lambdas outside a VPC have no fixed outbound IP, so customers cannot allowlist Konforme by IP.
