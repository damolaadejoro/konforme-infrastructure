#!/bin/bash
set -euo pipefail

# Deploy script called by GitLab CI.
# Usage: deploy.sh <EC2_HOST> <EC2_USER> <ECR_REPO_URL> <IMAGE_TAG> <AWS_REGION>

EC2_HOST="${1:?EC2_HOST required}"
EC2_USER="${2:-ec2-user}"
ECR_REPO_URL="${3:?ECR_REPO_URL required}"
IMAGE_TAG="${4:?IMAGE_TAG required}"
AWS_REGION="${5:-eu-west-1}"
APP_DIR="/opt/konforme"

echo "=== Deploying $ECR_REPO_URL:$IMAGE_TAG to $EC2_HOST ==="

ssh -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" bash <<REMOTE
set -euo pipefail

# Authenticate to ECR
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO_URL"

# Pull new image
docker pull "$ECR_REPO_URL:$IMAGE_TAG"

# Tag as latest
docker tag "$ECR_REPO_URL:$IMAGE_TAG" "$ECR_REPO_URL:latest"

# Restart only the backend container
cd "$APP_DIR"
docker compose up -d --no-deps backend

# Wait for health check
echo "Waiting for backend to become healthy..."
for i in {1..30}; do
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "Health check passed!"
    exit 0
  fi
  echo "  Attempt \$i/30..."
  sleep 5
done

echo "ERROR: Health check failed after 30 attempts"
exit 1
REMOTE

echo "=== Deployment complete ==="
