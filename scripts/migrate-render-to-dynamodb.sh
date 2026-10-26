#!/bin/bash
set -euo pipefail

# One-time copy of the Render PostgreSQL database into the DynamoDB table.
# Runs on your own machine, using your local AWS login and Docker:
#
#   export RENDER_DATABASE_URL='postgresql://...'   # Render → database → "External Database URL"
#   ./scripts/migrate-render-to-dynamodb.sh <BACKEND_IMAGE_URI> [--dry-run]
#
# BACKEND_IMAGE_URI is the Lambda image pushed in step 2 of the README (it contains
# the migration script). Pause the Render backend first so nothing is written after the copy.

IMAGE="${1:?Usage: $0 <backend-image-uri> [--dry-run]}"
EXTRA_ARGS="${2:-}"
REGION="eu-west-1"
TABLE="konforme"
: "${RENDER_DATABASE_URL:?Set RENDER_DATABASE_URL to Render's External Database URL}"

echo "=== Pulling migration image ==="
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${IMAGE%%/*}"
docker pull --platform linux/amd64 "$IMAGE"

if [ "$EXTRA_ARGS" != "--dry-run" ]; then
  echo "=== Safety backup: pg_dump to ./render-backup-*.dump ==="
  BACKUP_FILE="render-backup-$(date +%Y%m%d-%H%M%S).dump"
  docker run --rm -e PGURL="$RENDER_DATABASE_URL" postgres:16-alpine \
    sh -c 'pg_dump "$PGURL" --format=custom' > "$BACKUP_FILE"
  echo "Saved $BACKUP_FILE (keep it until the new site has run fine for a while)"
fi

echo "=== Copying PostgreSQL -> DynamoDB table '$TABLE' ==="
eval "$(aws configure export-credentials --format env)"
docker run --rm --platform linux/amd64 \
  --entrypoint /bin/sh \
  -e POSTGRES_URL="$RENDER_DATABASE_URL" \
  -e DYNAMODB_TABLE="$TABLE" -e DYNAMODB_REGION="$REGION" -e AWS_DEFAULT_REGION="$REGION" \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  "$IMAGE" \
  -c "pip install --quiet psycopg2-binary==2.9.10 && python3 scripts/migrate_postgres_to_dynamodb.py $EXTRA_ARGS"

echo
echo "=== Done. Next: ==="
echo "  1. aws lambda invoke --function-name konforme-migrate /dev/stdout   (refresh reference data)"
echo "  2. Point api/app DNS at AWS in Netlify (terraform output dns_records)"
