# kubernetes Module - Variables file for the kubernetes module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

variable "region" {}
variable "availability_zone_names" {}
variable "account_id" {}
variable "vpc_id" {}
variable "tdecision_namespace" {}
variable "redis_sentinel_chart" {}
variable "cert_manager_chart" {}
variable "external_secrets_chart" {}
variable "reloader_chart" {}
variable "jwt_ssh_private" {}
variable "jwt_ssh_public" {}
variable "okta_oidc" {}
variable "azure_oidc" {}
variable "google_oidc" {}
variable "certificate_arn" {}
variable "domain" {}
variable "main_subdomain" {}
variable "api_subdomain" {}
variable "secrets_access_role_arn" {}
variable "bucket_name" {}
variable "access_point_alias" {}
variable "public_volume_id" {}
variable "redis_role_arn" {}
variable "eks_service_cidr" {}
variable "db_name" {}
variable "db_endpoint" {}
variable "cluster_name" {}
variable "eks_oidc_issuer" {}
