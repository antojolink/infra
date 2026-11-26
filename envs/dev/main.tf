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