# Main - Modules instantion
#
# Andrei Pirjol (andrei.pirjol@oracle.com)
# Bogdan Darie (bogdan.m.darie@oracle.com)
# Ionut Sturzu (ionut.sturzu@oracle.com)
#
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (February 2019)
#
# Copyright Oracle, Inc.  All rights reserved.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.4.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.12.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">=1.14.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">=4.0.1"
    }
    random = {
      source  = "hashicorp/random"
      version = ">=3.3.2"
    }
  }
  backend "s3" {
    bucket               = "dng-terraform"
    key                  = "terraform.state"
    region               = "eu-central-1"
    workspace_key_prefix = "3decision-quickstart"
    encrypt              = "true"
  }
}

provider "aws" {
  region = "eu-central-1"
}

provider "kubernetes" {
  config_path = module.oke.filename
}

provider "helm" {
  kubernetes {
    config_path = module.oke.filename
  }
}

provider "kubectl" {
  config_path = module.oke.filename
}

provider "tls" {
}

provider "random" {
}

###############
# DATA SOURCES
###############

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

############
# MODULES
############

module "network" {
  source = "./modules/network"
  # Input
}

module "eks" {
  source = "./modules/eks"
  # Input
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
}

module "database" {
  source = "./modules/database"
  # Input
  node_security_group_id = module.eks.node_security_group_id
  vpc_id                 = module.network.vpc_id
  private_subnet_ids     = module.network.private_subnet_ids
  account_id             = local.account_id
}

module "security" {
  source = "./modules/security"
  # Input
  node_security_group_id           = module.eks.node_security_group_id
  db_security_group_id             = module.database.db_security_group_id
  secrets_lambda_security_group_id = module.secrets.secrets_lambda_security_group_id
}

module "secrets" {
  source = "./modules/secrets"
  # Input
  account_id           = local.account_id
  vpc_id               = module.network.vpc_id
  db_security_group_id = module.database.db_security_group_id
  private_subnet_ids   = module.network.private_subnet_ids
  db_name              = module.database.db_name
  db_endpoint          = module.database.db_endpoint
}

module "volumes" {
  source = "./modules/volumes"
  # Input
}

module "storage" {
  source = "./modules/storage"
  # Input
  account_id      = local.account_id
  vpc_id          = module.network.vpc_id
  eks_oidc_issuer = module.eks.eks_oidc_issuer
}

#module "kubernetes" {
#  source = "./modules/kubernetes"
#
#  # Input
#  depends_on = [module.eks]
#}

#module "dns" {
#  source = "./modules/dns"
#  # Input
#  depends_on = [module.kubernetes]
#}
