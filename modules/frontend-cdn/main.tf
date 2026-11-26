# Variante de Prod del modulo frontend: buckets privados servidos por CloudFront (HTTPS).
# Nadie lee los buckets directo; solo CloudFront, mediante Origin Access Control (OAC).

variable "env" {
  type = string
}

data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  sites      = toset(["admin", "menu"])
}

# ---------- Buckets privados ----------

resource "aws_s3_bucket" "site" {
  for_each      = local.sites
  bucket        = "antojolink-${each.key}-${var.env}-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket" "images" {
  bucket        = "antojolink-images-${var.env}-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  for_each                = local.sites
  bucket                  = aws_s3_bucket.site[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- CloudFront ----------

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "antojolink-${var.env}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Imita el modo "website" de S3: /ruta y /ruta/ -> /ruta/index.html.
# Si ese archivo no existe, S3 responde 403 y custom_error_response entrega /index.html (fallback SPA).
resource "aws_cloudfront_function" "rewrite" {
  name    = "antojolink-${var.env}-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOF
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
      } else if (uri.split('/').pop().indexOf('.') === -1) {
        request.uri = uri + '/index.html';
      }
      return request;
    }
  EOF
}

resource "aws_cloudfront_distribution" "site" {
  for_each            = local.sites
  enabled             = true
  comment             = "antojolink ${each.key} ${var.env}"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site[each.key].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
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

resource "aws_cloudfront_distribution" "images" {
  enabled     = true
  comment     = "antojolink images ${var.env}"
  price_class = "PriceClass_100"

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.images.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
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

# ---------- Politicas: solo la distribucion correspondiente puede leer ----------

resource "aws_s3_bucket_policy" "site" {
  for_each   = local.sites
  bucket     = aws_s3_bucket.site[each.key].id
  depends_on = [aws_s3_bucket_public_access_block.site]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site[each.key].arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site[each.key].arn }
      }
    }]
  })
}

resource "aws_s3_bucket_policy" "images" {
  bucket     = aws_s3_bucket.images.id
  depends_on = [aws_s3_bucket_public_access_block.images]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.images.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.images.arn }
      }
    }]
  })
}

# El admin sube imagenes con URL prefirmada directo a S3 (PUT), por eso S3 necesita CORS.
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_methods = ["PUT", "GET"]
    allowed_origins = ["https://${aws_cloudfront_distribution.site["admin"].domain_name}"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# ---------- Salidas (mismos nombres que el modulo frontend) ----------

output "admin_bucket" {
  value = aws_s3_bucket.site["admin"].bucket
}

output "menu_bucket" {
  value = aws_s3_bucket.site["menu"].bucket
}

output "images_bucket" {
  value = aws_s3_bucket.images.bucket
}

output "admin_url" {
  value = "https://${aws_cloudfront_distribution.site["admin"].domain_name}"
}

output "menu_url" {
  value = "https://${aws_cloudfront_distribution.site["menu"].domain_name}"
}

output "images_base_url" {
  value = "https://${aws_cloudfront_distribution.images.domain_name}"
}

output "admin_distribution_id" {
  value = aws_cloudfront_distribution.site["admin"].id
}

output "menu_distribution_id" {
  value = aws_cloudfront_distribution.site["menu"].id
}
