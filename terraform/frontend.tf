# --- Frontend: S3 + CloudFront for app.<domain> ---

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend-${local.account_id}"

  tags = {
    Purpose = "frontend-static-site"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn }
        }
      }
    ]
  })
}

# CloudFront requires its certificate in us-east-1
resource "aws_acm_certificate" "app" {
  count             = var.use_custom_domains ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = local.app_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS is on Netlify: add the record from `terraform output dns_records` there.
# Terraform waits here until AWS sees it.
resource "aws_acm_certificate_validation" "app" {
  count           = var.use_custom_domains ? 1 : 0
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.app[0].arn
}

# Same security headers the site had on Netlify, with the API added to connect-src
resource "aws_cloudfront_response_headers_policy" "frontend" {
  name = "${local.name_prefix}-frontend-security"

  security_headers_config {
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: https:",
        "font-src 'self' data:",
        "connect-src 'self' ${local.api_url}",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
      ])
      override = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    xss_protection {
      protection = true
      mode_block = true
      override   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "geolocation=(), microphone=(), camera=(), payment=()"
      override = true
    }
  }
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = var.use_custom_domains ? [local.app_fqdn] : []
  comment             = "${local.name_prefix} frontend"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-frontend"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.frontend.id
  }

  # SPA routing: unknown paths serve index.html (S3 returns 403 for missing keys under OAC)
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !var.use_custom_domains
    acm_certificate_arn            = var.use_custom_domains ? aws_acm_certificate_validation.app[0].certificate_arn : null
    ssl_support_method             = var.use_custom_domains ? "sni-only" : null
    minimum_protocol_version       = var.use_custom_domains ? "TLSv1.2_2021" : "TLSv1"
  }
}
