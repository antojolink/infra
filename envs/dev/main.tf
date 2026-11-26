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
    key          = "dev/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Project     = "antojolink"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

module "auth" {
  source = "../../modules/auth"
  env    = "dev"
}

output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_client_id" {
  value = module.auth.client_id
}

module "network" {
  source   = "../../modules/network"
  env      = "dev"
  vpc_cidr = "10.10.0.0/16"
}

output "vpc_id" {
  value = module.network.vpc_id
}

module "database" {
  source             = "../../modules/database"
  env                = "dev"
  private_subnet_ids = module.network.private_subnet_ids
  db_sg_id           = module.network.db_sg_id
}

output "db_endpoint" {
  value = module.database.endpoint
}

module "frontend" {
  source               = "../../modules/frontend"
  env                  = "dev"
  extra_upload_origins = ["http://localhost:5173"]
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

module "backend" {
  source               = "../../modules/backend"
  env                  = "dev"
  node_env             = "development"
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
    "http://localhost:5173",
    "http://localhost:4321",
  ]
}

output "ec2_instance_id" {
  value = module.backend.instance_id
}

output "api_url" {
  value = module.backend.api_url
}
module "monitoring" {
  source        = "../../modules/monitoring"
  env           = "dev"
  instance_id   = module.backend.instance_id
  db_identifier = module.database.identifier
  log_group     = module.backend.log_group
}

output "dashboard_url" {
  value = module.monitoring.dashboard_url
}
