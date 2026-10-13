#!/bin/bash
set -euo pipefail

# One-time copy of the production PostgreSQL database (EC2 container) into DynamoDB.
# Run ON the EC2 host, which can reach the Postgres container and has an IAM role
# allowed to write the table (dynamodb.tf: ec2_dynamodb_migration):
#
#   scp scripts/migrate-ec2-to-dynamodb.sh ec2-user@<EC2_IP>:
#   ssh ec2-user@<EC2_IP> ./migrate-ec2-to-dynamodb.sh <BACKEND_IMAGE_URI> [--dry-run]
#
# BACKEND_IMAGE_URI is the Lambda image pushed in Phase 1 (it contains the migration
# script). The backend container is stopped first so nothing is written after the copy;
# the site is down from then until cutover_to_lambda is applied.

IMAGE="${1:?Usage: $0 <backend-image-uri> [--dry-run]}"
EXTRA_ARGS="${2:-}"
APP_DIR="/opt/konforme"
REGION="eu-west-1"
TABLE="konforme"
COMPOSE=(docker compose -f "$APP_DIR/docker-compose.yml")

PGPASSWORD="$(aws ssm get-parameter --region "$REGION" --name /konforme/postgres_password \
  --with-decryption --query Parameter.Value --output text)"
PG_PASSWORD_ENC="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PGPASSWORD")"
BACKUPS_BUCKET="$(aws ssm get-parameter --region "$REGION" --name /konforme/s3_backups_bucket \
  --query Parameter.Value --output text)"

DB_CONTAINER="$("${COMPOSE[@]}" ps -q db)"
NETWORK="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$DB_CONTAINER")"

echo "=== Pulling migration image ==="
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${IMAGE%%/*}"
docker pull "$IMAGE"

if [ "$EXTRA_ARGS" != "--dry-run" ]; then
  echo "=== Stopping backend (maintenance window starts) ==="
  "${COMPOSE[@]}" stop backend

  echo "=== Safety backup: pg_dump to s3://$BACKUPS_BUCKET ==="
  BACKUP_FILE="/tmp/konforme-$(date +%Y%m%d-%H%M%S).dump"
  "${COMPOSE[@]}" exec -T db pg_dump -U konforme -d konforme --format=custom > "$BACKUP_FILE"
  aws s3 cp "$BACKUP_FILE" "s3://$BACKUPS_BUCKET/migration/$(basename "$BACKUP_FILE")"
fi

echo "=== Copying PostgreSQL -> DynamoDB table '$TABLE' ==="
# Instance-role credentials are passed explicitly; containers may not reach IMDS
eval "$(aws configure export-credentials --format env)"
docker run --rm --network "$NETWORK" \
  --entrypoint /bin/sh \
  -e POSTGRES_URL="postgresql://konforme:${PG_PASSWORD_ENC}@db:5432/konforme" \
  -e DYNAMODB_TABLE="$TABLE" -e DYNAMODB_REGION="$REGION" -e AWS_DEFAULT_REGION="$REGION" \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  "$IMAGE" \
  -c "pip install --quiet psycopg2-binary==2.9.10 && python3 scripts/migrate_postgres_to_dynamodb.py $EXTRA_ARGS"

echo
echo "=== Done. Next: ==="
echo "  1. aws lambda invoke --function-name konforme-migrate /dev/stdout   (refresh reference data)"
echo "  2. terraform apply -var cutover_to_lambda=true"
echo "To roll back instead: ${COMPOSE[*]} start backend"
