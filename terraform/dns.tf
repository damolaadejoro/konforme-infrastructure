# --- Route53 ---

data "aws_route53_zone" "main" {
  name         = "${var.domain_name}."
  private_zone = false
}

# api/app point at EC2 until var.cutover_to_lambda is set, then at API Gateway / CloudFront.

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.api_fqdn
  type    = "A"
  ttl     = var.cutover_to_lambda ? null : 300
  records = var.cutover_to_lambda ? null : [aws_eip.main.public_ip]

  dynamic "alias" {
    for_each = var.cutover_to_lambda ? [1] : []
    content {
      name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
      zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
      evaluate_target_health = false
    }
  }
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.app_fqdn
  type    = "A"
  ttl     = var.cutover_to_lambda ? null : 300
  records = var.cutover_to_lambda ? null : [aws_eip.main.public_ip]

  dynamic "alias" {
    for_each = var.cutover_to_lambda ? [1] : []
    content {
      name                   = aws_cloudfront_distribution.frontend.domain_name
      zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
      evaluate_target_health = false
    }
  }
}

resource "aws_route53_record" "app_ipv6" {
  count   = var.cutover_to_lambda ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.app_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = ["75.2.60.5"]
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["konforme.netlify.app"]
}
