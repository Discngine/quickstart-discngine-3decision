# database Module - Output file for the database module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

output "db_security_group_id" {
  value = aws_security_group.db_security_group.id
}

output "db_name" {
  value = aws_db_instance.db_instance.db_name
}

output "db_endpoint" {
  value = element(split(":", aws_db_instance.db_instance.endpoint), 0)
}
