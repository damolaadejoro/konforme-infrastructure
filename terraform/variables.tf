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

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
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
