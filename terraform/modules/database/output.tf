# database Module - Output file for the database module

output "db_security_group_id" {
  value = aws_security_group.db_security_group.id
}

output "db_name" {
  value = aws_db_instance.db_instance.db_name
}

output "db_endpoint" {
  value = aws_db_instance.db_instance.endpoint
}

output "db_instance_identifier" {
  value = aws_db_instance.db_instance.identifier
}

output "admin_username" {
  value = upper(aws_db_instance.db_instance.username)
}

output "database_arn" {
  value = aws_db_instance.db_instance.arn
}

output "s3_integration_ready" {
  description = "Indicates S3 integration is ready (reboot completed)"
  value       = var.enable_s3_integration ? null_resource.reboot_for_s3_integration[0].id : null
}
