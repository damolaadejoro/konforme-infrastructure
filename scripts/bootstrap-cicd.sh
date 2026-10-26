#!/bin/bash
set -euo pipefail

# One-time setup so GitHub Actions can deploy to AWS. Run from your machine with a
# working AWS login and `gh` logged in, after terraform/terraform.tfvars is filled in:
#
#   ./scripts/bootstrap-cicd.sh
#
# 1. Creates the GitHub login provider + deploy roles in AWS (nothing else)
# 2. Copies secret_key / encryption_key from terraform.tfvars into GitHub secrets
# 3. Sets AWS_ROLE_ARN in the three repos
# After this, merging to main in konforme-infrastructure builds everything.

OWNER="damolaadejoro"
INFRA_REPO="$OWNER/konforme-infrastructure"
cd "$(dirname "$0")/../terraform"

echo "=== Creating GitHub deploy roles in AWS ==="
terraform init -input=false > /dev/null
terraform apply -input=false -auto-approve \
  -target=aws_iam_role_policy_attachment.github_infra \
  -target=aws_iam_role.github

tfvar() { sed -nE "s/^$1[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" terraform.tfvars; }

echo "=== Setting GitHub secrets (production environment) ==="
for name in secret_key encryption_key resend_api_key; do
  value="$(tfvar "$name")"
  if [ -n "$value" ]; then
    printf '%s' "$value" | gh secret set "TF_VAR_${name^^}" -R "$INFRA_REPO" --env production
  fi
done

echo "=== Setting AWS_ROLE_ARN variables ==="
ROLE_PREFIX="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/konforme-github"
gh variable set AWS_ROLE_ARN -R "$INFRA_REPO" --env production -b "$ROLE_PREFIX-infra"
gh variable set AWS_ROLE_ARN -R "$OWNER/Konforme-project-" -b "$ROLE_PREFIX-backend"
gh variable set AWS_ROLE_ARN -R "$OWNER/konforme-frontend" -b "$ROLE_PREFIX-frontend"

echo "=== Done. Merge the infrastructure PR and approve the run to build everything. ==="
