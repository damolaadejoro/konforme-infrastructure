variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "konforme"
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "konforme.io"
}

variable "api_subdomain" {
  description = "Subdomain for the API"
  type        = string
  default     = "api"
}

variable "app_subdomain" {
  description = "Subdomain for the frontend app"
  type        = string
  default     = "app"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "data_volume_size" {
  description = "Postgres data EBS volume size in GB"
  type        = number
  default     = 20
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed SSH access"
  type        = list(string)
}

variable "ssh_key_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
}

# --- Application secrets (stored in SSM) ---

variable "secret_key" {
  description = "FastAPI SECRET_KEY (>= 32 chars)"
  type        = string
  sensitive   = true
}

variable "encryption_key" {
  description = "Fernet encryption key for AWS credentials"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "konforme_aws_account_id" {
  description = "AWS Account ID where Konforme runs (for STS AssumeRole trust)"
  type        = string
}

variable "allowed_origins" {
  description = "Comma-separated allowed CORS origins"
  type        = string
  default     = "https://app.konforme.io"
}

variable "budget_alert_email" {
  description = "Email address for budget alerts"
  type        = string
  default     = ""
}

variable "budget_limit_usd" {
  description = "Monthly budget alarm threshold"
  type        = number
  default     = 20
}

# --- Serverless stack ---

variable "cutover_to_lambda" {
  description = "Point api/app DNS at API Gateway/CloudFront and enable the daily jobs. Leave false until the data migration is done."
  type        = bool
  default     = false
}

variable "lambda_image_tag" {
  description = "Initial ECR image tag for the backend Lambdas (CI deploys later images directly)"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table holding all application data"
  type        = string
  default     = "konforme"
}

variable "api_throttle_burst" {
  description = "API Gateway burst limit"
  type        = number
  default     = 100
}

variable "api_throttle_rate" {
  description = "API Gateway steady-state requests per second"
  type        = number
  default     = 50
}

variable "email_provider" {
  description = "Email provider: resend or ses"
  type        = string
  default     = "resend"
}

variable "resend_api_key" {
  description = "Resend API key (when email_provider = resend)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sender_email" {
  description = "From address for outgoing email"
  type        = string
  default     = "noreply@konforme.io"
}

variable "signup_webhook_url" {
  description = "Optional webhook notified on new signups"
  type        = string
  default     = ""
  sensitive   = true
}

# --- GitHub Actions (OIDC) ---

variable "github_owner" {
  description = "GitHub user/org that owns the repos"
  type        = string
  default     = "damolaadejoro"
}

variable "github_backend_repo" {
  description = "Backend repository name"
  type        = string
  default     = "Konforme-project-"
}

variable "github_frontend_repo" {
  description = "Frontend repository name"
  type        = string
  default     = "konforme-frontend"
}

variable "github_infra_repo" {
  description = "Infrastructure repository name"
  type        = string
  default     = "konforme-infrastructure"
}
