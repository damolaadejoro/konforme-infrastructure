output "api_url" {
  description = "API endpoint URL"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for backend images"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_login_command" {
  description = "Command to authenticate Docker to ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.backend.repository_url}"
}

output "app_url" {
  description = "Frontend app URL"
  value       = "https://${local.app_fqdn}"
}

output "s3_evidence_bucket" {
  description = "S3 bucket for evidence uploads"
  value       = aws_s3_bucket.evidence.id
}

output "s3_reports_bucket" {
  description = "S3 bucket for PDF reports"
  value       = aws_s3_bucket.reports.id
}


# --- Serverless stack ---

output "api_gateway_url" {
  description = "Default API Gateway URL (test before cutover; disabled after)"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "dynamodb_table" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.main.name
}

output "frontend_bucket" {
  description = "S3 bucket the frontend is deployed to"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (frontend cache invalidation)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain" {
  description = "CloudFront domain (test before cutover)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "github_role_arns" {
  description = "IAM roles for GitHub Actions — set as AWS_ROLE_ARN in each repo"
  value       = { for k, r in aws_iam_role.github : k => r.arn }
}

output "dns_records" {
  description = "Records to add in Netlify DNS: certificate checks now, api/app at cutover"
  value = {
    certificate_checks = [
      for o in concat(tolist(aws_acm_certificate.api.domain_validation_options), tolist(aws_acm_certificate.app.domain_validation_options)) : {
        type  = o.resource_record_type
        name  = o.resource_record_name
        value = o.resource_record_value
      }
    ]
    at_cutover = {
      (local.api_fqdn) = { type = "CNAME", value = try(aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name, "(after full apply)") }
      (local.app_fqdn) = { type = "CNAME", value = try(aws_cloudfront_distribution.frontend.domain_name, "(after full apply)") }
    }
  }
}
