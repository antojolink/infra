variable "env" {
  type = string
}

variable "extra_upload_origins" {
  type    = list(string)
  default = []
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  sites      = toset(["admin", "menu"])
}

# ---------- Sitios: admin y menu ----------

resource "aws_s3_bucket" "site" {
  for_each      = local.sites
  bucket        = "antojolink-${each.key}-${var.env}-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  for_each                = local.sites
  bucket                  = aws_s3_bucket.site[each.key].id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "site" {
  for_each = local.sites
  bucket   = aws_s3_bucket.site[each.key].id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "site" {
  for_each   = local.sites
  bucket     = aws_s3_bucket.site[each.key].id
  depends_on = [aws_s3_bucket_public_access_block.site]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site[each.key].arn}/*"
    }]
  })
}

# ---------- Imágenes ----------

resource "aws_s3_bucket" "images" {
  bucket        = "antojolink-images-${var.env}-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "images" {
  bucket     = aws_s3_bucket.images.id
  depends_on = [aws_s3_bucket_public_access_block.images]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.images.arn}/*"
    }]
  })
}

resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_methods = ["PUT", "GET"]
    allowed_origins = concat(
      ["http://${aws_s3_bucket_website_configuration.site["admin"].website_endpoint}"],
      var.extra_upload_origins
    )
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# ---------- Salidas ----------

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
  value = "http://${aws_s3_bucket_website_configuration.site["admin"].website_endpoint}"
}

output "menu_url" {
  value = "http://${aws_s3_bucket_website_configuration.site["menu"].website_endpoint}"
}

output "images_base_url" {
  value = "https://${aws_s3_bucket.images.bucket_regional_domain_name}"
}