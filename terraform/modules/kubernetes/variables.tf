# kubernetes Module - Variables file for the kubernetes module

variable "region" {}
variable "availability_zone_names" {}
variable "account_id" {}
variable "vpc_id" {}
variable "tdecision_chart" {}
variable "choral_chart" {}
variable "redis_sentinel_chart" {}
variable "chemaxon_ms_chart" {}
variable "cert_manager_chart" {}
variable "external_secrets_chart" {}
variable "reloader_chart" {}
variable "jwt_ssh_private" {}
variable "jwt_ssh_public" {}
variable "okta_oidc" {}
variable "azure_oidc" {}
variable "google_oidc" {}
variable "certificate_arn" {}
variable "inbound_cidrs" {}
variable "domain" {}
variable "main_subdomain" {}
variable "additional_main_fqdns" {}
variable "api_subdomain" {}
variable "registration_subdomain" {}
variable "load_balancer_type" {}
variable "additional_eks_roles_arn" {}
variable "additional_eks_users_arn" {}
variable "custom_ami" {}
variable "secrets_access_role_arn" {}
variable "alphafold_bucket_name" {}
variable "alphafold_s3_role_arn" {}
variable "public_volume_id" {}
variable "private_volume_id" {}
variable "eks_service_cidr" {}
variable "db_name" {}
variable "db_endpoint" {}
variable "cluster_name" {}
variable "eks_oidc_issuer" {}
variable "node_group_role_arn" {}
variable "af_file_name" {}
variable "af_ftp_link" {}
variable "af_file_nb" {}
variable "initial_db_passwords" {}
variable "force_destroy" {}
