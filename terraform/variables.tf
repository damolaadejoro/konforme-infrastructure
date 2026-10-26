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

# --- Application secrets ---

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

variable "konforme_aws_account_id" {
  description = "AWS account customers trust in their KonformeAuditRole (empty = the account Terraform deploys to)"
  type        = string
  default     = ""
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

variable "use_custom_domains" {
  description = "Serve on api./app.<domain_name>. Needs the certificate check records added in Netlify DNS (terraform output dns_records). False = AWS's own URLs."
  type        = bool
  default     = false
}

variable "cutover_to_lambda" {
  description = "Set true once api/app DNS points at AWS: turns on the daily jobs and turns off the default API Gateway URL. Leave false until the data migration is done."
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
