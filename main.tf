terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default Provider: vrm-sandbox (App Account)
provider "aws" {
  alias  = "app_account"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${var.app_account_id}:role/TerraformDeploymentRole"
  }
}

# Secondary Provider: vrm-ai (Agent Account)
provider "aws" {
  alias  = "agent_account"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${var.agent_account_id}:role/TerraformDeploymentRole"
  }
}

# Data Lookups for Existing Infrastructure
data "aws_vpc" "existing_app_vpc" {
  provider = aws.app_account
  id       = var.existing_app_vpc_id
}

data "aws_vpc" "existing_agent_vpc" {
  provider = aws.agent_account
  id       = var.existing_agent_vpc_id
}

data "aws_subnets" "agent_private_subnets" {
  provider = aws.agent_account
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_agent_vpc.id]
  }
  filter {
    name   = "tag:Tier"
    values = ["Private"]
  }
}

data "aws_lb" "existing_internal_alb" {
  provider = aws.app_account
  arn      = var.existing_internal_alb_arn
}

data "aws_iam_role" "existing_sidekiq_irsa" {
  provider = aws.app_account
  name     = var.existing_sidekiq_irsa_role_name
}

# Module Deployments
module "agent_execution_layer" {
  source                   = "./modules/agent_ai_account"
  providers                = { aws = aws.agent_account }
  agent_vpc_id             = data.aws_vpc.existing_agent_vpc.id
  agent_private_subnet_ids = data.aws_subnets.agent_private_subnets.ids
  app_account_id           = var.app_account_id
  sidekiq_irsa_role_arn    = data.aws_iam_role.existing_sidekiq_irsa.arn
  container_image_uri      = var.agent_runtime_image_uri
  aws_region               = var.aws_region
}

module "app_tools_lattice_layer" {
  source                = "./modules/app_account_lattice"
  providers             = { aws = aws.app_account }
  app_vpc_id            = data.aws_vpc.existing_app_vpc.id
  agent_account_id      = var.agent_account_id
  internal_alb_arn      = data.aws_lb.existing_internal_alb.arn
  internal_alb_dns_name = data.aws_lb.existing_internal_alb.dns_name
}