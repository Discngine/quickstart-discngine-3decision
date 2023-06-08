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
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">=2.10.1"
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
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
  load_config_file = false
}

provider "tls" {
}

provider "random" {
}

###############
# DATA SOURCES
###############

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  account_id              = data.aws_caller_identity.current.account_id
  availability_zone_names = data.aws_availability_zones.available.names
}

############
# MODULES
############

module "network" {
  count  = var.create_network ? 1 : 0
  source = "./modules/network"
  # Input
}

module "eks" {
  source = "./modules/eks"
  # Input
  region             = var.region
  account_id         = local.account_id
  kubernetes_version = var.kubernetes_version
  custom_ami         = var.custom_ami
  instance_type      = var.eks_instance_type
  boot_volume_size   = var.boot_volume_size
  # Output
  vpc_id             = var.create_network ? module.network[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_network ? module.network[0].private_subnet_ids : var.private_subnet_ids

  depends_on = [module.network]
}

module "database" {
  source = "./modules/database"
  # Input
  region                  = var.region
  account_id              = local.account_id
  force_destroy           = var.force_destroy
  snapshot_identifier     = var.db_snapshot_identifier
  high_availability       = var.db_high_availability
  instance_type           = var.db_instance_type
  backup_retention_period = var.db_backup_retention_period
  license_type            = var.license_type
  # Output
  node_security_group_id = module.eks.node_security_group_id
  vpc_id                 = var.create_network ? module.network[0].vpc_id : var.vpc_id
  private_subnet_ids     = var.create_network ? module.network[0].private_subnet_ids : var.private_subnet_ids
}

module "security" {
  source = "./modules/security"
  # Output
  node_security_group_id           = module.eks.node_security_group_id
  db_security_group_id             = module.database.db_security_group_id
  secrets_lambda_security_group_id = module.secrets.secrets_lambda_security_group_id
}

module "secrets" {
  source = "./modules/secrets"
  # Input
  region               = var.region
  account_id           = local.account_id
  initial_db_passwords = var.initial_db_passwords
  # Output
  vpc_id               = var.create_network ? module.network[0].vpc_id : var.vpc_id
  private_subnet_ids   = var.create_network ? module.network[0].private_subnet_ids : var.private_subnet_ids
  db_security_group_id = module.database.db_security_group_id
  db_name              = module.database.db_name
  db_endpoint          = module.database.db_endpoint
  node_group_role_arn  = module.eks.node_group_role_arn
}

module "volumes" {
  source = "./modules/volumes"
  # Input
  region                  = var.region
  availability_zone_names = local.availability_zone_names
  public_volume_snapshot  = var.public_volume_snapshot
  private_volume_snapshot = var.private_volume_snapshot
}

module "storage" {
  source = "./modules/storage"
  # Input
  region        = var.region
  account_id    = local.account_id
  force_destroy = var.force_destroy
  # Output
  vpc_id          = var.create_network ? module.network[0].vpc_id : var.vpc_id
  eks_oidc_issuer = module.eks.oidc_issuer
}

module "kubernetes" {
  source = "./modules/kubernetes"

  # Input
  region                  = var.region
  availability_zone_names = local.availability_zone_names
  account_id              = local.account_id
  tdecision_namespace     = var.tdecision_namespace
  redis_sentinel_chart    = var.redis_sentinel_chart
  cert_manager_chart      = var.cert_manager_chart
  external_secrets_chart  = var.external_secrets_chart
  reloader_chart          = var.reloader_chart
  okta_oidc               = var.okta_oidc
  azure_oidc              = var.azure_oidc
  google_oidc             = var.google_oidc
  certificate_arn         = var.certificate_arn
  domain                  = var.domain
  main_subdomain          = var.main_subdomain
  api_subdomain           = var.api_subdomain
  # Output
  vpc_id                  = var.create_network ? module.network[0].vpc_id : var.vpc_id
  jwt_ssh_private         = module.secrets.jwt_private_key
  jwt_ssh_public          = module.secrets.jwt_public_key
  secrets_access_role_arn = module.secrets.secrets_access_role_arn
  bucket_name             = module.storage.bucket_name
  access_point_alias      = module.storage.access_point_alias
  public_volume_id        = module.volumes.public_volume_id
  private_volume_id       = module.volumes.private_volume_id
  redis_role_arn          = module.storage.redis_role_arn
  eks_service_cidr        = module.eks.service_cidr
  db_name                 = module.database.db_name
  db_endpoint             = module.database.db_endpoint
  cluster_name            = module.eks.cluster_name
  eks_oidc_issuer         = module.eks.oidc_issuer

  depends_on = [module.eks]
}

module "dns" {
  source = "./modules/dns"
  # Input
  domain         = var.domain
  main_subdomain = var.main_subdomain
  api_subdomain  = var.api_subdomain
  zone_id        = var.zone_id
  # Output
  cluster_id = module.eks.cluster_id
  depends_on = [module.kubernetes]
}
