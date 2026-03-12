# Data Migration Module - Simplified Variables
# One-time Oracle Data Pump import from S3

variable "run_data_migration" {
  description = "Whether to run the data migration job"
  type        = bool
  default     = true
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "s3_key" {
  description = "S3 key (path) to the dump file in dng-psilo-license bucket"
  type        = string
  default     = ""
}

variable "db_endpoint" {
  description = "RDS database endpoint (hostname:port)"
  type        = string
}

variable "db_name" {
  description = "Database name/SID"
  type        = string
}

variable "s3_role_association_id" {
  description = "ID of the RDS S3 role association (dependency marker)"
  type        = string
  default     = null
}

variable "rds_s3_role_arn" {
  description = "ARN of the IAM role for RDS S3 integration"
  type        = string
  default     = null
}
