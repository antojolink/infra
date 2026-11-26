variable "env" { type = string }
variable "subnet_id" { type = string }
variable "api_sg_id" { type = string }
variable "images_bucket" { type = string }
variable "images_base_url" { type = string }
variable "database_url" {
  type      = string
  sensitive = true
}
variable "cognito_user_pool_id" { type = string }
variable "cognito_client_id" { type = string }
variable "cors_origins" { type = list(string) }
variable "node_env" { type = string }

variable "api_image" {
  type    = string
  default = "antojolink/sass-core:latest"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  log_group = "/antojolink/${var.env}/api"
}

# ---------- Rol de la EC2 ----------

resource "aws_iam_role" "ec2" {
  name = "antojolink-${var.env}-ec2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",
  ])
  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "images" {
  name = "images-bucket"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject"]
      Resource = "arn:aws:s3:::${var.images_bucket}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "antojolink-${var.env}-ec2"
  role = aws_iam_role.ec2.name
}

# ---------- Logs ----------

resource "aws_cloudwatch_log_group" "api" {
  name              = local.log_group
  retention_in_days = 7
}

# ---------- EC2 ----------

resource "aws_instance" "api" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.api_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    env                  = var.env
    node_env             = var.node_env
    database_url         = var.database_url
    cognito_user_pool_id = var.cognito_user_pool_id
    cognito_client_id    = var.cognito_client_id
    images_bucket        = var.images_bucket
    images_base_url      = var.images_base_url
    cors_origins         = join(",", var.cors_origins)
    api_image            = var.api_image
    log_group            = local.log_group
  })

  tags = { Name = "antojolink-${var.env}-api" }

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [aws_cloudwatch_log_group.api]
}

resource "aws_eip" "api" {
  instance = aws_instance.api.id
  domain   = "vpc"
  tags     = { Name = "antojolink-${var.env}-api" }
}

output "instance_id" {
  value = aws_instance.api.id
}

output "public_ip" {
  value = aws_eip.api.public_ip
}

output "api_url" {
  value = "http://${aws_eip.api.public_ip}"
}
output "log_group" {
  value = aws_cloudwatch_log_group.api.name
}

output "public_dns" {
  value = aws_eip.api.public_dns
}
