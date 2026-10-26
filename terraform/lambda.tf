# --- Backend Lambda Functions ---
# One container image (konforme-backend/Dockerfile.lambda) backs three functions:
#   api     — HTTP traffic from API Gateway
#   worker  — cloud scans (async invoke from api) and the daily scheduled jobs
#   migrate — seed reference data (base controls, mappings), invoked by CI after each deploy
#
# CI updates the image on every deploy, so Terraform ignores image_uri after creation.

locals {
  lambda_image_uri = "${aws_ecr_repository.backend.repository_url}:${var.lambda_image_tag}"

  lambda_functions = {
    api = {
      handler     = "lambda_handler.api"
      timeout     = 29 # API Gateway integration limit is 30s
      memory_size = 1024
    }
    worker = {
      handler     = "lambda_handler.worker"
      timeout     = 900
      memory_size = 1024
    }
    migrate = {
      handler     = "lambda_handler.migrate"
      timeout     = 300
      memory_size = 1024
    }
  }

  lambda_environment = {
    ENVIRONMENT             = "production"
    DYNAMODB_TABLE          = aws_dynamodb_table.main.name
    DYNAMODB_REGION         = var.aws_region
    SECRET_KEY              = var.secret_key
    ENCRYPTION_KEY          = var.encryption_key
    ALLOWED_ORIGINS         = var.use_custom_domains ? var.allowed_origins : local.app_url
    KONFORME_AWS_ACCOUNT_ID = local.konforme_aws_account_id
    COOKIE_DOMAIN           = var.use_custom_domains ? ".${var.domain_name}" : ""
    COOKIE_SECURE           = "true"
    COOKIE_SAMESITE         = "none"
    FRONTEND_BASE_URL       = local.app_url
    UPLOAD_DIR              = "/tmp/evidence"
    REPORT_STORAGE_PATH     = "/tmp/reports"
    S3_EVIDENCE_BUCKET      = aws_s3_bucket.evidence.id
    S3_EVIDENCE_REGION      = var.aws_region
    S3_REPORTS_BUCKET       = aws_s3_bucket.reports.id
    S3_REPORTS_REGION       = var.aws_region
    EMAIL_PROVIDER          = var.email_provider
    RESEND_API_KEY          = var.resend_api_key
    SENDER_EMAIL            = var.sender_email
    AWS_SES_REGION          = var.aws_region
    SIGNUP_WEBHOOK_URL      = var.signup_webhook_url
    WORKER_FUNCTION_NAME    = "${local.name_prefix}-worker"
  }
}

# --- IAM ---

resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_app" {
  name = "${local.name_prefix}-lambda-app"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AppTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:ConditionCheckItem",
          "dynamodb:Query",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [aws_dynamodb_table.main.arn, "${aws_dynamodb_table.main.arn}/index/*"]
      },
      {
        Sid    = "AppBuckets"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.evidence.arn,
          "${aws_s3_bucket.evidence.arn}/*",
          aws_s3_bucket.reports.arn,
          "${aws_s3_bucket.reports.arn}/*",
        ]
      },
      {
        # Scanning customer AWS accounts (KonformeAuditRole pattern)
        Sid      = "CustomerAuditRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/KonformeAuditRole"
      },
      {
        Sid      = "DispatchScans"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${local.name_prefix}-worker"
      },
      {
        Sid      = "SendEmail"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  })
}

# --- Functions ---

resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambda_functions

  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = 30
}

resource "aws_lambda_function" "backend" {
  for_each = local.lambda_functions

  function_name = "${local.name_prefix}-${each.key}"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = local.lambda_image_uri
  architectures = ["x86_64"]
  timeout       = each.value.timeout
  memory_size   = each.value.memory_size

  image_config {
    command = [each.value.handler]
  }

  environment {
    variables = local.lambda_environment
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_logs,
  ]

  lifecycle {
    ignore_changes = [image_uri]
  }
}

# Scans must not be retried automatically — a retry would start a second scan
resource "aws_lambda_function_event_invoke_config" "worker" {
  function_name          = aws_lambda_function.backend["worker"].function_name
  maximum_retry_attempts = 0
}

# --- Daily jobs (replaces APScheduler) ---

locals {
  scheduled_jobs = {
    overdue_reminders           = "cron(0 8 * * ? *)"
    chronic_slip_escalation     = "cron(15 8 * * ? *)"
    roll_people_task_periods    = "cron(5 0 * * ? *)"
    detect_overdue_people_tasks = "cron(30 8 * * ? *)"
  }
}

resource "aws_iam_role" "scheduler" {
  name = "${local.name_prefix}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "${local.name_prefix}-scheduler-invoke"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.backend["worker"].arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "jobs" {
  for_each = local.scheduled_jobs

  name                         = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  schedule_expression          = each.value
  schedule_expression_timezone = "UTC"
  # Stays off until cutover so EC2 and Lambda don't both send reminder emails
  state = var.cutover_to_lambda ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.backend["worker"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ task = "scheduled_job", job = each.key })
  }
}

# --- API Gateway (HTTP API) ---

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  # CORS is handled by FastAPI's CORSMiddleware
  disable_execute_api_endpoint = var.cutover_to_lambda && var.use_custom_domains
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.backend["api"].invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = 30
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst
    throttling_rate_limit  = var.api_throttle_rate
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      method    = "$context.httpMethod"
      path      = "$context.path"
      status    = "$context.status"
      latencyMs = "$context.integrationLatency"
      error     = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend["api"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# --- api.<domain> custom domain ---

resource "aws_acm_certificate" "api" {
  count             = var.use_custom_domains ? 1 : 0
  domain_name       = local.api_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS is on Netlify: add the record from `terraform output dns_records` there.
# Terraform waits here until AWS sees it.
resource "aws_acm_certificate_validation" "api" {
  count           = var.use_custom_domains ? 1 : 0
  certificate_arn = aws_acm_certificate.api[0].arn
}

resource "aws_apigatewayv2_domain_name" "api" {
  count       = var.use_custom_domains ? 1 : 0
  domain_name = local.api_fqdn

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api[0].certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "api" {
  count       = var.use_custom_domains ? 1 : 0
  api_id      = aws_apigatewayv2_api.main.id
  domain_name = aws_apigatewayv2_domain_name.api[0].id
  stage       = aws_apigatewayv2_stage.default.id
}
