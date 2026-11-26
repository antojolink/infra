# CloudFront delante de la EC2 para que la API tenga HTTPS (*.cloudfront.net) sin dominio propio.
# Sin cache y con todos los metodos: CloudFront solo hace de "tunel" HTTPS -> HTTP:80 de Nginx.

variable "env" {
  type = string
}

variable "origin_domain" {
  description = "DNS publico de la IP elastica de la EC2 (CloudFront no acepta IPs como origen)"
  type        = string
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Reenvia headers (incluido Authorization), query strings y cookies, excepto Host.
data "aws_cloudfront_origin_request_policy" "all_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "api" {
  enabled     = true
  comment     = "antojolink api ${var.env}"
  price_class = "PriceClass_100"

  origin {
    origin_id   = "ec2"
    domain_name = var.origin_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "ec2"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_except_host.id
    compress                 = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "api_url" {
  value = "https://${aws_cloudfront_distribution.api.domain_name}"
}
