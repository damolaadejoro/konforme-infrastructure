output "ec2_public_ip" {
  description = "Elastic IP of the EC2 instance"
  value       = aws_eip.main.public_ip
}

output "api_url" {
  description = "API endpoint URL"
  value       = "https://${var.api_subdomain}.${var.domain_name}"
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.main.public_ip}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for backend images"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_login_command" {
  description = "Command to authenticate Docker to ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.backend.repository_url}"
}

output "frontend_bucket_name" {
  description = "S3 bucket name for frontend"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for frontend"
  value       = aws_cloudfront_distribution.frontend.id
}

output "app_url" {
  description = "Frontend app URL"
  value       = "https://${local.app_fqdn}"
}

