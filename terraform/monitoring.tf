# --- CloudWatch Log Groups ---

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/${var.project_name}/backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/${var.project_name}/nginx"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/${var.project_name}/postgres"
  retention_in_days = 14
}

# --- Budget Alarm ($20/mo threshold) ---

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_email != "" ? [var.budget_alert_email] : []
  }
}
