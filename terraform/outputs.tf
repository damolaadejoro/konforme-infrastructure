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

output "s3_backups_bucket" {
  description = "S3 bucket for database backups"
  value       = aws_s3_bucket.backups.id
}

