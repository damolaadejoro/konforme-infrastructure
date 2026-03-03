# --- Route53 ---

data "aws_route53_zone" "main" {
  name         = "${var.domain_name}."
  private_zone = false
}

resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.api_fqdn
  type    = "A"
  ttl     = 300
  records = [aws_eip.main.public_ip]
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.app_fqdn
  type    = "A"
  ttl     = 300
  records = [aws_eip.main.public_ip]
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
