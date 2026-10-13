# --- DynamoDB: all application data in one table ---
# Key layout and index meaning are documented in konforme-backend/store.py.

resource "aws_dynamodb_table" "main" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  deletion_protection_enabled = true

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }
  attribute {
    name = "entity"
    type = "S"
  }
  attribute {
    name = "eid"
    type = "S"
  }

  dynamic "attribute" {
    for_each = local.dynamodb_lookup_indexes
    content {
      name = attribute.value
      type = "S"
    }
  }

  # Get any item by id, and list every item of one type (daily jobs)
  global_secondary_index {
    name            = "by-entity"
    hash_key        = "entity"
    range_key       = "eid"
    projection_type = "ALL"
  }

  # Lookups without knowing the account: login email, invite/verify/reset tokens, ...
  dynamic "global_secondary_index" {
    for_each = local.dynamodb_lookup_indexes
    content {
      name            = global_secondary_index.value
      hash_key        = global_secondary_index.value
      projection_type = "KEYS_ONLY"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  dynamodb_lookup_indexes = ["lk_email", "lk_token", "lk_verify", "lk_reset"]
}

# Temporary: lets the data-migration container on EC2 write the table.
# Remove together with the EC2 resources (Phase 3).
resource "aws_iam_role_policy" "ec2_dynamodb_migration" {
  name = "${local.name_prefix}-dynamodb-migration"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = [aws_dynamodb_table.main.arn, "${aws_dynamodb_table.main.arn}/index/*"]
      }
    ]
  })
}
