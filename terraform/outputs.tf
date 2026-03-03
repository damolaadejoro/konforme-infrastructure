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

output "gitlab_ci_access_key_id" {
  description = "AWS Access Key ID for GitLab CI (set as CI variable)"
  value       = aws_iam_access_key.gitlab_ci.id
  sensitive   = true
}

output "gitlab_ci_secret_access_key" {
  description = "AWS Secret Access Key for GitLab CI (set as CI variable)"
  value       = aws_iam_access_key.gitlab_ci.secret
  sensitive   = true
}
