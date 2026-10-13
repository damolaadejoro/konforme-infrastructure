# --- GitHub Actions → AWS via OIDC (no long-lived keys in GitHub) ---
# Replaces the konforme-gitlab-ci IAM user.

variable "create_github_oidc_provider" {
  description = "Set false if the account already has the token.actions.githubusercontent.com provider"
  type        = bool
  default     = true
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # subject = the only GitHub context allowed to assume each role
  github_roles = {
    backend  = "repo:${var.github_owner}/${var.github_backend_repo}:ref:refs/heads/main"
    frontend = "repo:${var.github_owner}/${var.github_frontend_repo}:ref:refs/heads/main"
    # Requires the workflow job to use `environment: production` (set up approvals there)
    infra = "repo:${var.github_owner}/${var.github_infra_repo}:environment:production"
  }
}

resource "aws_iam_role" "github" {
  for_each = local.github_roles

  name = "${local.name_prefix}-github-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = local.github_oidc_arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = each.value
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_backend" {
  name = "deploy-backend"
  role = aws_iam_role.github["backend"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = aws_ecr_repository.backend.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:InvokeFunction"
        ]
        Resource = [for f in aws_lambda_function.backend : f.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_frontend" {
  name = "deploy-frontend"
  role = aws_iam_role.github["frontend"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.frontend.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.frontend.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = aws_cloudfront_distribution.frontend.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_infra" {
  role       = aws_iam_role.github["infra"].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
