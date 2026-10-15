data "aws_db_snapshot" "source" {
  count = var.copy_db_snapshot ? 0 : 1

  db_snapshot_identifier = local.snapshot_identifier
  include_shared         = true
  include_public         = true
}

locals {
  snapshot_identifier = var.snapshot_identifier != "" ? var.snapshot_identifier : "arn:aws:rds:${var.region}:751149478800:snapshot:db3dec"

  # Will set to the copied identifier if not set
  final_snapshot_identifier = var.copy_db_snapshot ? aws_db_snapshot_copy.snapshot[0].db_snapshot_arn : local.snapshot_identifier

  # RDS cannot shrink storage, and the provider forces allocated_storage with a ModifyDBInstance right after
  # the snapshot restore, so never request less than the snapshot size.
  snapshot_allocated_storage = var.copy_db_snapshot ? aws_db_snapshot_copy.snapshot[0].allocated_storage : data.aws_db_snapshot.source[0].allocated_storage
  allocated_storage          = max(coalesce(var.allocated_storage, 0), local.snapshot_allocated_storage)
}
