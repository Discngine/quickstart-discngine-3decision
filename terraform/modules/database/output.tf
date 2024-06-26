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
