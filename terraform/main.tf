# Main - Modules instantion

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.37.1"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "= 2.1.3"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.2"
    }
  }
  backend "s3" {
    key                  = "terraform.state"
    workspace_key_prefix = "3decision-quickstart"
    encrypt              = "true"
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = var.default_tags
  }
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

data "aws_vpc" "vpc" {
  count = var.vpc_id != "" ? 1 : 0

  id = var.vpc_id
}

locals {
  account_id              = data.aws_caller_identity.current.account_id
  availability_zone_names = data.aws_availability_zones.available.names
}

###################
# GLOBAL RESOURCES
###################

resource "aws_kms_key" "kms" {
  count = var.create_kms_key ? 1 : 0

  description              = "3decision KMS CMK"
  enable_key_rotation      = true
  is_enabled               = true
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  deletion_window_in_days  = 30
}

locals {
  kms_key_id = var.create_kms_key ? aws_kms_key.kms[0].arn : var.kms_key_arn
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
  region                 = var.region
  account_id             = local.account_id
  keypair_name           = var.keypair_name
  k8s_public_access      = var.k8s_public_access
  kubernetes_version     = var.kubernetes_version
  custom_ami             = var.custom_ami
  instance_type          = var.eks_instance_type
  boot_volume_size       = var.boot_volume_size
  create_cluster         = var.create_cluster
  create_node_group      = var.create_node_group
  cluster_name           = var.eks_cluster_name
  user_data              = var.eks_node_user_data
  create_openid_provider = var.create_openid_provider
  openid_provider_arn    = var.openid_provider_arn
  add_pia_addon          = var.add_pia_addon
  use_pia                = var.use_pia
  # Output
  vpc_cidr           = var.vpc_id != "" ? data.aws_vpc.vpc[0].cidr_block : "10.0.0.0/16"
  vpc_id             = var.create_network ? module.network[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_network ? module.network[0].private_subnet_ids : (length(var.eks_private_subnet_ids) > 0 ? var.eks_private_subnet_ids : var.private_subnet_ids)

  depends_on = [module.network]
}

module "database" {
  source = "./modules/database"
  # Input
  region                     = var.region
  account_id                 = local.account_id
  force_destroy              = var.force_destroy
  snapshot_identifier        = var.db_snapshot_identifier
  copy_db_snapshot           = var.copy_db_snapshot
  copied_snapshot_identifier = var.copied_snapshot_identifier
  high_availability          = var.db_high_availability
  instance_type              = var.db_instance_type
  backup_retention_period    = var.db_backup_retention_period
  delete_automated_backups   = var.db_delete_automated_backups
  license_type               = var.license_type
  skip_final_snapshot        = var.skip_db_final_snapshot
  kms_key_id                 = local.kms_key_id
  max_allocated_storage      = var.max_allocated_storage
  storage_type               = var.db_storage_type
  # Output
  node_security_group_id = var.create_node_group ? module.eks.node_security_group_id : var.node_group_security_group_id
  vpc_id                 = var.create_network ? module.network[0].vpc_id : var.vpc_id
  private_subnet_ids     = var.create_network ? module.network[0].private_subnet_ids : var.private_subnet_ids
}

module "security" {
  source = "./modules/security"
  # Output
  node_security_group_id           = var.create_node_group ? module.eks.node_security_group_id : var.node_group_security_group_id
  db_security_group_id             = module.database.db_security_group_id
  secrets_lambda_security_group_id = module.secrets.secrets_lambda_security_group_id
}

module "secrets" {
  source = "./modules/secrets"
  # Input
  region               = var.region
  account_id           = local.account_id
  initial_db_passwords = var.initial_db_passwords

  enable_db_user_rotation    = var.enable_db_user_rotation
  db_user_rotation_schedule  = var.db_user_rotation_schedule
  db_admin_rotation_schedule = var.db_admin_rotation_schedule

  use_pia = var.use_pia
  # Output
  vpc_id                 = var.create_network ? module.network[0].vpc_id : var.vpc_id
  private_subnet_ids     = var.create_network ? module.network[0].private_subnet_ids : var.private_subnet_ids
  db_security_group_id   = module.database.db_security_group_id
  db_name                = module.database.db_name
  db_endpoint            = module.database.db_endpoint
  node_group_role_arn    = var.create_node_group ? module.eks.node_group_role_arn : var.node_group_arn
  cluster_name           = module.eks.cluster_name
  admin_username         = module.database.admin_username
  db_instance_identifier = module.database.db_instance_identifier
  database_arn           = module.database.database_arn
}

module "volumes" {
  source = "./modules/volumes"
  # Input
  region                           = var.region
  availability_zone_names          = local.availability_zone_names
  encrypt_volumes                  = var.encrypt_volumes
  volumes_additional_tags          = var.volumes_additional_tags
  storage_type                     = var.volumes_storage_type
  public_volume_snapshot           = var.public_volume_snapshot
  private_volume_snapshot          = var.private_volume_snapshot
  private_final_snapshot           = var.private_final_snapshot
  public_final_snapshot            = var.public_final_snapshot
  kms_key_id                       = local.kms_key_id
  private_volume_availability_zone = var.private_volume_availability_zone
  public_volume_availability_zone  = var.public_volume_availability_zone
}

locals {
  buckets = toset(["alphafold", "app"])
  allowed_service_accounts = {
    "alphafold" = ["system:serviceaccount:tdecision:*"]
  }
}

module "storage" {
  for_each = local.buckets
  source   = "./modules/storage"

  # Input
  account_id               = local.account_id
  name                     = each.key
  region                   = var.region
  force_destroy            = each.key == "alphafold" ? true : var.force_destroy
  allowed_service_accounts = lookup(local.allowed_service_accounts, each.key, [])

  # Output
  vpc_id              = var.create_network ? module.network[0].vpc_id : var.vpc_id
  eks_oidc_issuer     = module.eks.oidc_issuer
  openid_provider_arn = module.eks.openid_provider_arn
}

module "kubernetes" {
  source = "./modules/kubernetes"

  # Input
  region                     = var.region
  availability_zone_names    = local.availability_zone_names
  account_id                 = local.account_id
  tdecision_chart            = var.tdecision_chart
  postgres_chart             = var.postgres_chart
  redis_sentinel_chart       = var.redis_sentinel_chart
  cert_manager_chart         = var.cert_manager_chart
  external_secrets_chart     = var.external_secrets_chart
  reloader_chart             = var.reloader_chart
  kubernetes_reflector_chart = var.kubernetes_reflector_chart
  okta_oidc                  = var.okta_oidc
  azure_oidc                 = var.azure_oidc
  google_oidc                = var.google_oidc
  pingid_oidc                = var.pingid_oidc
  certificate_arn            = var.certificate_arn
  inbound_cidrs              = var.inbound_cidrs
  domain                     = var.domain
  main_subdomain             = var.main_subdomain
  additional_main_fqdns      = var.additional_main_fqdns
  api_subdomain              = var.api_subdomain
  registration_subdomain     = var.registration_subdomain
  load_balancer_type         = var.load_balancer_type
  additional_eks_roles_arn   = var.additional_eks_roles_arn
  additional_eks_users_arn   = var.additional_eks_users_arn
  custom_ami                 = var.custom_ami
  af_file_name               = var.af_file_name
  af_ftp_link                = var.af_ftp_link
  af_file_nb                 = var.af_file_nb
  initial_db_passwords       = var.initial_db_passwords
  force_destroy              = var.force_destroy
  encrypt_volumes            = var.encrypt_volumes
  deploy_cert_manager        = var.deploy_cert_manager
  deploy_alb_chart           = var.deploy_alb_chart
  use_pia                    = var.use_pia
  username_is_email          = var.username_is_email
  # Output
  vpc_id                           = var.create_network ? module.network[0].vpc_id : var.vpc_id
  jwt_ssh_private                  = module.secrets.jwt_private_key
  jwt_ssh_public                   = module.secrets.jwt_public_key
  secrets_access_role_arn          = module.secrets.secrets_access_role_arn
  alphafold_bucket_name            = module.storage["alphafold"].bucket_name
  alphafold_s3_role_arn            = module.storage["alphafold"].s3_role_arn
  app_bucket_name                  = module.storage["app"].bucket_name
  public_volume_id                 = module.volumes.public_volume_id
  private_volume_id                = module.volumes.private_volume_id
  eks_service_cidr                 = module.eks.service_cidr
  db_name                          = module.database.db_name
  db_endpoint                      = module.database.db_endpoint
  cluster_name                     = module.eks.cluster_name
  eks_oidc_issuer                  = module.eks.oidc_issuer
  node_group_role_arn              = var.create_node_group ? module.eks.node_group_role_arn : var.node_group_arn
  public_volume_availability_zone  = var.public_volume_availability_zone
  private_volume_availability_zone = var.private_volume_availability_zone

  depends_on = [module.eks]
}

module "dns" {
  count  = var.hosted_zone_id != "" ? 1 : 0
  source = "./modules/dns"
  # Input
  domain                 = var.domain
  main_subdomain         = var.main_subdomain
  api_subdomain          = var.api_subdomain
  registration_subdomain = var.registration_subdomain
  zone_id                = var.hosted_zone_id

  depends_on = [module.kubernetes.tdecision_release]
}
