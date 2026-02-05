# Main - Modules output

#####################
# DATA MIGRATION
#####################

output "data_migration_rds_role_arn" {
  description = "IAM role ARN for RDS S3 integration - provide this to Discngine"
  value       = module.data_migration.rds_s3_role_arn
}

output "data_migration_job_name" {
  description = "Name of the migration Kubernetes job"
  value       = module.data_migration.job_name
}

output "data_migration_status_command" {
  description = "kubectl command to check migration status"
  value       = module.data_migration.status_command
}

output "data_migration_logs_command" {
  description = "kubectl command to view migration logs"
  value       = module.data_migration.logs_command
}
