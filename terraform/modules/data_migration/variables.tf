# Data Migration Module - Simplified Variables
# One-time Oracle Data Pump import from S3

variable "run_data_migration" {
  description = "Whether to run the data migration job"
  type        = bool
  default     = false
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
