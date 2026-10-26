data "aws_caller_identity" "current" {}

locals {
  name_prefix = var.project_name
  api_fqdn    = "${var.api_subdomain}.${var.domain_name}"
  app_fqdn    = "${var.app_subdomain}.${var.domain_name}"
  account_id  = data.aws_caller_identity.current.account_id

  # Account customers trust in their KonformeAuditRole (defaults to this one)
  konforme_aws_account_id = coalesce(var.konforme_aws_account_id, local.account_id)

  # Public URLs: konforme.io names once use_custom_domains is on, AWS's own URLs until then
  api_url = var.use_custom_domains ? "https://${local.api_fqdn}" : aws_apigatewayv2_api.main.api_endpoint
  app_url = var.use_custom_domains ? "https://${local.app_fqdn}" : "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

# --- ECR Repository ---

resource "aws_ecr_repository" "backend" {
  name                 = "${local.name_prefix}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
