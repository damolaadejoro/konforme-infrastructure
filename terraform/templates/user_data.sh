#!/bin/bash
set -euo pipefail
exec > /var/log/user-data.log 2>&1

echo "=== Konforme EC2 Bootstrap ==="

# --- Install Docker ---
dnf update -y
dnf install -y docker aws-cli jq
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Install Docker Compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# --- Mount EBS Volume for Postgres Data ---
DATA_DEVICE="${data_device}"
DATA_MOUNT="/data/postgres"

mkdir -p "$DATA_MOUNT"

# Format only if not already formatted
if ! blkid "$DATA_DEVICE" | grep -q ext4; then
  echo "Formatting $DATA_DEVICE..."
  mkfs.ext4 "$DATA_DEVICE"
fi

# Add to fstab if not already present
if ! grep -q "$DATA_MOUNT" /etc/fstab; then
  echo "$DATA_DEVICE $DATA_MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

mount -a
chmod 700 "$DATA_MOUNT"

# --- Fetch SSM Parameters and Write .env ---
APP_DIR="/opt/${project_name}"
mkdir -p "$APP_DIR"

REGION="${aws_region}"
PREFIX="/${project_name}"

fetch_param() {
  aws ssm get-parameter \
    --region "$REGION" \
    --name "$PREFIX/$1" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text
}

cat > "$APP_DIR/.env" <<EOF
DATABASE_URL=$(fetch_param database_url)
SECRET_KEY=$(fetch_param secret_key)
ENCRYPTION_KEY=$(fetch_param encryption_key)
POSTGRES_PASSWORD=$(fetch_param postgres_password)
ENVIRONMENT=$(fetch_param environment)
ALLOWED_ORIGINS=$(fetch_param allowed_origins)
KONFORME_AWS_ACCOUNT_ID=$(fetch_param konforme_aws_account_id)
COOKIE_DOMAIN=$(fetch_param cookie_domain)
COOKIE_SECURE=$(fetch_param cookie_secure)
COOKIE_SAMESITE=$(fetch_param cookie_samesite)
EOF

chmod 600 "$APP_DIR/.env"

# --- Pull ECR Image ---
ECR_REPO="${ecr_repo_url}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPO"

# Pull latest image (will be tagged by CI)
docker pull "$ECR_REPO:latest" || echo "No image yet — will be deployed by CI"

# --- Write docker-compose.prod.yml ---
cat > "$APP_DIR/docker-compose.yml" <<'COMPOSE'
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: konforme
      POSTGRES_USER: konforme
      POSTGRES_PASSWORD: $${POSTGRES_PASSWORD}
    volumes:
      - /data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U konforme"]
      interval: 10s
      timeout: 5s
      retries: 5

  backend:
    image: ${ecr_repo_url}:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    env_file:
      - .env
    ports:
      - "127.0.0.1:8000:8000"
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
COMPOSE

# --- Start Containers ---
cd "$APP_DIR"
docker compose --env-file .env up -d

# --- Install and Configure Nginx ---
dnf install -y nginx

cat > /etc/nginx/conf.d/${project_name}.conf <<'NGINX'
server {
    listen 80;
    server_name ${api_fqdn};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
NGINX

mkdir -p /var/www/certbot
systemctl enable nginx
systemctl start nginx

# --- Let's Encrypt SSL ---
dnf install -y certbot python3-certbot-nginx

certbot --nginx \
  -d "${api_fqdn}" \
  --non-interactive \
  --agree-tos \
  --email "admin@${api_fqdn}" \
  --redirect \
  || echo "Certbot failed — will retry manually"

# Write the final Nginx config with proxy
cat > /etc/nginx/conf.d/${project_name}.conf <<'NGINXSSL'
server {
    listen 80;
    server_name ${api_fqdn};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${api_fqdn};

    ssl_certificate /etc/letsencrypt/live/${api_fqdn}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${api_fqdn}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXSSL

nginx -t && systemctl reload nginx

# --- Certbot Auto-Renewal Cron ---
echo "0 3 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew

echo "=== Bootstrap Complete ==="
