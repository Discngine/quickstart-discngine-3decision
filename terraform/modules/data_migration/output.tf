# Data Migration Module - Outputs


output "job_name" {
  description = "Migration job name"
  value       = var.run_data_migration ? "data-migration" : null
}

output "status_command" {
  description = "Command to check migration status"
  value       = var.run_data_migration ? "kubectl get job data-migration -n tdecision" : null
}

output "logs_command" {
  description = "Command to view migration logs"
  value       = var.run_data_migration ? "kubectl logs -n tdecision job/data-migration -f" : null
}

output "migration_completed" {
  description = "Marker that data migration job has completed successfully (tables validated)"
  value       = var.run_data_migration ? kubernetes_job_v1.migration[0].metadata[0].name : "skipped"
}
