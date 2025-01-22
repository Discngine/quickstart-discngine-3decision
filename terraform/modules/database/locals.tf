locals {
  snapshot_identifier = var.snapshot_identifier != "" ? var.snapshot_identifier : "arn:aws:rds:${var.region}:751149478800:snapshot:db3dec"

  # Will set to the copied identifier if not set
  final_snapshot_identifier = var.copy_db_snapshot ? aws_db_snapshot_copy.snapshot[0].db_snapshot_arn : local.snapshot_identifier
}
