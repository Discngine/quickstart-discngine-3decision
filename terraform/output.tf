# Main - Modules output

#####################
# DATA MIGRATION
#####################

output "data_migration_enabled" {
  description = "Whether data migration is enabled"
  value       = var.data_migration_enabled
}

output "data_migration_namespace" {
  description = "Kubernetes namespace where migration resources are deployed"
  value       = module.data_migration.migration_namespace
}

output "data_migration_job_name" {
  description = "Name of the migration Kubernetes job"
  value       = module.data_migration.migration_job_name
}

output "data_migration_status_command" {
  description = "kubectl command to check migration status"
  value       = module.data_migration.migration_status_command
}

output "data_migration_logs_command" {
  description = "kubectl command to view migration logs"
  value       = module.data_migration.migration_logs_command
}
