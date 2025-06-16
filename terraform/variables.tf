#################
# GLOBAL
#################

variable "region" {
  default     = "eu-central-1"
  description = "region into which to deploy the stack"
  validation {
    condition = anytrue([
      var.region == "eu-central-1",
      var.region == "us-east-1",
    ])
    error_message = "Only deployment into eu-central-1 and us-east-1 is supported, Contact discngine to deploy in another region."
  }
}

variable "default_tags" {
  default     = {}
  description = "Default tags to add to all resources"
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Setting this to false will not allow deletion of the database / non empty s3 buckets"
}

variable "kms_key_arn" {
  default     = null
  description = "KMS key arn to use if create_kms_key is set to false"
}

variable "create_kms_key" {
  default     = false
  description = "Whether to create a kms key for the database and volumes"
}

###########
# NETWORK
###########

variable "create_network" {
  type        = bool
  default     = false
  description = "Whether to create network. Leave to false to deploy in your own network."
}

variable "vpc_id" {
  default     = ""
  description = "Id of your VPC. Required when create_network is set to false"
}

variable "private_subnet_ids" {
  type        = set(string)
  default     = []
  description = "List of ids of your private subnets"
}

variable "eks_private_subnet_ids" {
  type        = set(string)
  default     = []
  description = "List of ids of your private eks subnets"
}

#########
# EKS
#########

variable "create_cluster" {
  default     = true
  description = "Whether to create the eks cluster."
}

variable "create_node_group" {
  default     = true
  description = "Whether to create a node group."
}

variable "node_group_arn" {
  default     = ""
  description = "Arn of the node group used for permissions if the node group isn't created."
}

variable "node_group_security_group_id" {
  default     = ""
  description = "Id of the node group security group use if the node group isn't created."
}

variable "eks_cluster_name" {
  default     = ""
  description = "Name of the existing cluster if not created"
}

variable "eks_node_user_data" {
  default     = ""
  description = "User data to pass to nodes instead of default"
}

variable "keypair_name" {
  default     = ""
  description = "Name of keypair to add to EKS nodes"
}

variable "k8s_public_access" {
  default     = true
  description = "Whether we can connect to the k8s control plane through the internet"
}

variable "kubernetes_version" {
  default     = "1.27"
  description = "EKS version of the control plane"
}

variable "custom_ami" {
  default     = ""
  description = "Arn of an ami to use for the EKS nodegroup"
}

variable "eks_instance_type" {
  default     = "t3.2xlarge"
  description = "Instance type of the EKS nodes"
}

variable "boot_volume_size" {
  default     = "50"
  description = "default size of the eks boot volumes"
}

variable "additional_eks_roles_arn" {
  type        = list(string)
  description = "Arn of roles to add as administrators to the eks cluster. If the role is a path (containing several /) remove what is between the first and last ones"
  default     = []
}

variable "additional_eks_users_arn" {
  type        = list(string)
  description = "Arn of users to add as administrators to the eks cluster."
  default     = []
}

variable "create_openid_provider" {
  default     = true
  description = "Whether to create an iam openid provider connected to EKS. Set openid_provider_arn if set to false"
}

variable "openid_provider_arn" {
  default     = ""
  description = "Arn of an existing openid provider used if create_openid_provider is set to false."
}

variable "external_secrets_pia" {
  type        = bool
  default     = false
  description = "Set to true to use pod identity association for external secrets. Otherwise the node role user credentials are used."
}

variable "add_pia_addon" {
  type        = bool
  default     = false
  description = "Set to true to add the pod identity association addon to the cluster"
}

###############
# DATABASE
###############

variable "copy_db_snapshot" {
  default     = false
  description = "Will copy the db_snapshot_identifier and encrypt it"
}

variable "copied_snapshot_identifier" {
  type        = string
  default     = "db3dec"
  description = "Name of the copied database snapshot"
}

variable "db_snapshot_identifier" {
  default     = ""
  description = "Arn of a database snapshot. If left empty the public unencrypted snapshot will be used."
}

variable "db_high_availability" {
  type        = bool
  default     = false
  description = "Whether to activate high availability for the database"
}

variable "db_instance_type" {
  default     = "db.t3.xlarge"
  description = "Instance type of the RDS database"
}

variable "initial_db_passwords" {
  default = {
    "ADMIN"                   = "Ch4ng3m3f0rs3cur3p4ss"
    "CHEMBL_29"               = "Ch4ng3m3f0rs3cur3p4ss"
    "PD_T1_DNG_THREEDECISION" = "Ch4ng3m3f0rs3cur3p4ss"
  }
  description = "The passwords of the schemas present in the snapshot"
}

variable "enable_db_user_rotation" {
  default     = true
  type        = bool
  description = "Setting to false will disable rotation for database users"
}

variable "db_user_rotation_schedule" {
  default     = "cron(0 2 ? * SUN#1 *)"
  description = "Schedule expression to set for db users password rotation"
}

variable "db_admin_rotation_schedule" {
  default     = "cron(0 2 ? * SUN#1 *)"
  description = "Schedule expression to set for db admin user password rotation"
}

variable "db_backup_retention_period" {
  default     = 7
  description = "Number of days to keep database backups"
}

variable "db_delete_automated_backups" {
  default     = true
  description = "Whether to delete automated backups when the db instance is deleted"
}

variable "license_type" {
  default     = "license-included"
  description = "Whether the oracle license is BYOL or included"
  validation {
    condition = anytrue([
      var.license_type == "license-included",
      var.license_type == "bring-your-own-license",
    ])
    error_message = "License type can only be license-included or bring-your-own-license."
  }
}

variable "skip_db_final_snapshot" {
  default     = false
  description = "Whether to skip the creation of a db snpashot when deleting it"
}

variable "max_allocated_storage" {
  default     = 1000
  type        = number
  description = "Maximum autoscaled size of the database"
}

variable "db_storage_type" {
  default     = "gp2"
  type        = string
  description = "Type of storage for the database"
}

#################
# Load Balancing
#################

variable "load_balancer_type" {
  default     = "internal"
  description = "Whether to create an internal or internet-facing load balancer"
  validation {
    condition = anytrue([
      var.load_balancer_type == "internal",
      var.load_balancer_type == "internet-facing",
    ])
    error_message = "Load balancer type can either be internal or internet-facing."
  }
}

variable "certificate_arn" {
  default     = ""
  description = "Arn of the certificate to add to the loadbalancer"
}

variable "inbound_cidrs" {
  default     = ""
  description = "List of cidr blocks to allow access to the loadbalancer"
}

variable "domain" {
  description = "Root domain name used for load balancer rules. This is only the root domain name not the fqdn, eg: example.com"
}

variable "main_subdomain" {
  default     = "3decision"
  description = "Name used for the main app subdomain"
}

variable "additional_main_fqdns" {
  default     = []
  description = "Additional main subdomains that will redirect to the main_subdomain"
}

variable "api_subdomain" {
  default     = "3decision-api"
  description = "Name used for the api subdomain"
}

variable "registration_subdomain" {
  default     = "3decision-reg"
  description = "Name used for the registration subdomain"
}

variable "hosted_zone_id" {
  default     = ""
  description = "Route53 HostedZone id. If left empty, create DNS records manually after apply."
}

###############
# KUBERNETES
###############

variable "deploy_cert_manager" {
  default     = true
  description = "Whether to deploy the cert manager"
}

variable "deploy_alb_chart" {
  default     = true
  description = "Whether to deploy the alb chart"
}

variable "tdecision_chart" {
  description = "A map with information about the cert manager helm chart"

  type = object({
    name             = optional(string, "tdecision")
    chart            = optional(string, "oci://fra.ocir.io/discngine1/prod/helm/tdecision")
    namespace        = optional(string, "tdecision")
    version          = optional(string, "3.2.0-pingid")
    create_namespace = optional(bool, true)
  })
  default = {}
}

variable "postgres_chart" {
  description = "A map with information about the redis sentinel helm chart"

  type = object({
    name             = optional(string, "postgresql")
    chart            = optional(string, "oci://registry-1.docker.io/bitnamicharts/postgresql")
    namespace        = optional(string, "postgres")
    create_namespace = optional(bool, true)
    version          = optional(string, "16.7.3")
  })
  default = {}
}

variable "cert_manager_chart" {
  description = "A map with information about the cert manager helm chart"

  type = object({
    name             = optional(string, "cert-manager")
    repository       = optional(string, "https://charts.jetstack.io")
    chart            = optional(string, "cert-manager")
    namespace        = optional(string, "cert-manager")
    create_namespace = optional(bool, true)
    version          = optional(string, "1.8.0")
  })
  default = {}
}

variable "kubernetes_reflector_chart" {
  description = "A map with information about the reflector helm chart"

  type = object({
    name             = optional(string, "kubernetes-reflector")
    chart_name       = optional(string, "reflector")
    repository       = optional(string, "https://emberstack.github.io/helm-charts")
    namespace        = optional(string, "kubernetes-reflector")
    timeout          = optional(string, 300)
    create_namespace = optional(bool, true)
    version          = optional(string, "7.1.256")
  })
  default = {
    name             = "kubernetes-reflector"
    chart_name       = "reflector"
    repository       = "https://emberstack.github.io/helm-charts"
    namespace        = "kubernetes-reflector"
    timeout          = 300
    create_namespace = true
    version          = "7.1.256"
  }
}

variable "external_secrets_chart" {
  description = "A map with information about the external secrets operator helm chart"

  type = object({
    name             = optional(string, "external-secrets")
    repository       = optional(string, "https://charts.external-secrets.io")
    chart            = optional(string, "external-secrets")
    namespace        = optional(string, "external-secrets")
    create_namespace = optional(bool, true)
    version          = optional(string, "0.16.2")
  })
  default = {}
}

variable "reloader_chart" {
  description = "A map with information about the nginx controller helm chart"

  type = object({
    name             = optional(string, "reloader")
    repository       = optional(string, "https://stakater.github.io/stakater-charts")
    chart            = optional(string, "reloader")
    namespace        = optional(string, "reloader")
    create_namespace = optional(bool, true)
  })
  default = {}
}

variable "redis_sentinel_chart" {
  description = "A map with information about the redis sentinel helm chart"

  type = object({
    name             = optional(string, "sentinel")
    chart            = optional(string, "oci://fra.ocir.io/discngine1/prod/helm/redis")
    namespace        = optional(string, "redis-cluster")
    create_namespace = optional(bool, true)
    version          = optional(string, "21.1.3")
  })
  default = {}
}

variable "okta_oidc" {
  default = {
    client_id = "none"
    domain    = ""
    server_id = ""
    secret    = ""
  }
  description = "Okta Client ID for OKTA integration"
  sensitive   = true
}

variable "azure_oidc" {
  description = "Azure Client ID for authentication in application"
  default = {
    client_id = "none"
    tenant    = ""
    secret    = ""
  }
  sensitive = true
}

variable "google_oidc" {
  description = "Google Client ID for authentication in application"
  default = {
    client_id = "none"
    secret    = ""
  }
  sensitive = true
}

variable "pingid_oidc" {
  description = "PingID Client ID for authentication in application"
  default = {
    client_id    = "none"
    secret       = ""
    metadata_url = ""
  }
  sensitive = true
}

variable "username_is_email" {
  type        = bool
  default     = false
  description = "Set to true to use the email as the username in 3decision"
}

###########
# Volumes
###########

variable "volumes_storage_type" {
  default     = "gp2"
  type        = string
  description = "Type of storage for the database"
}

variable "volumes_additional_tags" {
  default     = {}
  type        = map(string)
  description = "Additional tags to add to the volumes"
}

variable "encrypt_volumes" {
  type        = bool
  default     = true
  description = "Whether to encrypt the volumes"
}

variable "public_volume_snapshot" {
  default     = ""
  description = "Snapshot id of the public data volume. If left empty the public snapshot will be used."
}

variable "private_volume_snapshot" {
  default     = ""
  description = "Used to recreate volume from snapshot in case of DR. Otherwise the volume will be empty"
}

variable "private_volume_availability_zone" {
  type        = number
  default     = 0
  description = "In which Availability zone to deploy the private volume"
}

variable "public_volume_availability_zone" {
  type        = number
  default     = 0
  description = "In which Availability zone to deploy the public volume"
}

variable "public_final_snapshot" {
  default     = true
  description = "Whether to create a snapshot of the public volume when deleting it"
}

variable "private_final_snapshot" {
  default     = true
  description = "Whether to create a snapshot of the public volume when deleting it"
}

###############
#     Alphafold
###############

variable "af_ftp_link" {
  default     = "https://ftp.ebi.ac.uk/pub/databases/alphafold/v4/"
  description = "url of the ftp to get the swissprot tar"
}

variable "af_file_name" {
  default     = "swissprot_pdb_v4.tar"
  description = "file name to downlaod from the ftp"
}

variable "af_file_nb" {
  default     = "542378"
  description = "number of files in archive"
}
