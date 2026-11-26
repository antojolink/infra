terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket       = "antojolink-tfstate-973429899380"
    key          = "prod/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Project     = "antojolink"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

module "auth" {
  source = "../../modules/auth"
  env    = "prod"
}

module "network" {
  source   = "../../modules/network"
  env      = "prod"
  vpc_cidr = "10.20.0.0/16"
}

module "database" {
  source             = "../../modules/database"
  env                = "prod"
  private_subnet_ids = module.network.private_subnet_ids
  db_sg_id           = module.network.db_sg_id
}

# Prod: buckets privados + CloudFront (HTTPS), en lugar del modo website publico de Dev
module "frontend" {
  source = "../../modules/frontend-cdn"
  env    = "prod"
}

module "backend" {
  source               = "../../modules/backend"
  env                  = "prod"
  node_env             = "production"
  api_image            = "alexfdzv/sass-core:latest"
  subnet_id            = module.network.public_subnet_ids[0]
  api_sg_id            = module.network.api_sg_id
  database_url         = module.database.database_url
  cognito_user_pool_id = module.auth.user_pool_id
  cognito_client_id    = module.auth.client_id
  images_bucket        = module.frontend.images_bucket
  images_base_url      = module.frontend.images_base_url
  cors_origins = [
    module.frontend.admin_url,
    module.frontend.menu_url,
  ]
}

# HTTPS para la API mientras no haya dominio (#12)
module "api_cdn" {
  source        = "../../modules/api-cdn"
  env           = "prod"
  origin_domain = module.backend.public_dns
}

module "monitoring" {
  source        = "../../modules/monitoring"
  env           = "prod"
  instance_id   = module.backend.instance_id
  db_identifier = module.database.identifier
  log_group     = module.backend.log_group
}

# ---------- Salidas (para cargar en los environments "prod" de GitHub) ----------

output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_client_id" {
  value = module.auth.client_id
}

output "db_endpoint" {
  value = module.database.endpoint
}

output "admin_bucket" {
  value = module.frontend.admin_bucket
}

output "menu_bucket" {
  value = module.frontend.menu_bucket
}

output "images_bucket" {
  value = module.frontend.images_bucket
}

output "admin_url" {
  value = module.frontend.admin_url
}

output "menu_url" {
  value = module.frontend.menu_url
}

output "images_base_url" {
  value = module.frontend.images_base_url
}

output "admin_distribution_id" {
  value = module.frontend.admin_distribution_id
}

output "menu_distribution_id" {
  value = module.frontend.menu_distribution_id
}

output "ec2_instance_id" {
  value = module.backend.instance_id
}

output "api_url" {
  value = module.api_cdn.api_url
}

output "dashboard_url" {
  value = module.monitoring.dashboard_url
}
