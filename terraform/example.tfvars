## Copyright © 2020, Oracle and/or its affiliates.
## All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl


# Replace by us-east-1 to deploy in NA
region = "eu-central-1"

# Set to true will force destroy RDS database & S3 buckets on stack destruction
force_destroy = false

# If set to false, give vpc_id and private_subnet_ids. Otherwise leave those blank
create_network = false
vpc_id = ""
private_subnet_ids = []

# Custom ami to use for EKS, if left null the default eks ami will be used
custom_ami = null

# Replace by a copied arn for an encrypted database
db_snapshot_identifier = null

# Whether to activate db high availability
db_high_availability = false

# Number of days to keep database backups
db_backup_retention_period = 7

# ARN of a certificate to add to the loadbalancer
certificate_arn = ""

# Domain information
domain = 
main_subdomain = "3decision"
api_subdomain = "3decision-api"

## ROUTE 53 Hosted zone id
hosted_zone_id = null

## Azure AD Information
azure_oidc = {
  client_id = "none"
  tenant    = ""
  secret    = ""
}

## OKTA AD Information
okta_oidc = {
  client_id = "none"
  domain    = ""
  server_id = ""
  secret    = ""
}

## Google AD Information
google_oidc = {
  client_id = "none"
  secret    = ""
}

# Can generally be left as is

kubernetes_version = "1.27"
public_volume_snapshot = null
db_instance_type = "db.t3.xlarge"
license_type = "license-included"
eks_instance_type = "t3.2xlarge"
boot_volume_size = "50"
public_final_snapshot = true
private_final_snapshot = true
