# --- SSM Parameter Store (app configuration) ---

resource "aws_ssm_parameter" "database_url" {
  name  = "/${var.project_name}/database_url"
  type  = "SecureString"
  value = "postgresql://konforme:${var.postgres_password}@db:5432/konforme?sslmode=disable"
}

resource "aws_ssm_parameter" "secret_key" {
  name  = "/${var.project_name}/secret_key"
  type  = "SecureString"
  value = var.secret_key
}

resource "aws_ssm_parameter" "encryption_key" {
  name  = "/${var.project_name}/encryption_key"
  type  = "SecureString"
  value = var.encryption_key
}

resource "aws_ssm_parameter" "postgres_password" {
  name  = "/${var.project_name}/postgres_password"
  type  = "SecureString"
  value = var.postgres_password
}

resource "aws_ssm_parameter" "environment" {
  name  = "/${var.project_name}/environment"
  type  = "String"
  value = "production"
}

resource "aws_ssm_parameter" "allowed_origins" {
  name  = "/${var.project_name}/allowed_origins"
  type  = "String"
  value = var.allowed_origins
}

resource "aws_ssm_parameter" "konforme_aws_account_id" {
  name  = "/${var.project_name}/konforme_aws_account_id"
  type  = "String"
  value = var.konforme_aws_account_id
}

resource "aws_ssm_parameter" "cookie_domain" {
  name  = "/${var.project_name}/cookie_domain"
  type  = "String"
  value = ".${var.domain_name}"
}

resource "aws_ssm_parameter" "cookie_secure" {
  name  = "/${var.project_name}/cookie_secure"
  type  = "String"
  value = "true"
}

resource "aws_ssm_parameter" "cookie_samesite" {
  name  = "/${var.project_name}/cookie_samesite"
  type  = "String"
  value = "none"
}
