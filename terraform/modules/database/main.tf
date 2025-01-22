# database Module - Main file for the database module

resource "aws_db_subnet_group" "subnet_group" {
  name_prefix = "private-subnets-group"
  description = "private subnets group"
  subnet_ids  = var.private_subnet_ids
}

resource "aws_security_group" "db_security_group" {
  name_prefix = "tdec-db-sg"
  description = "Opens incoming requests on Oracle RDS port 1521"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "db_security_group_egress" {
  type              = "egress"
  security_group_id = aws_security_group.db_security_group.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_db_snapshot_copy" "snapshot" {
  count = var.copy_db_snapshot ? 1 : 0

  source_db_snapshot_identifier = local.snapshot_identifier
  target_db_snapshot_identifier = var.copied_snapshot_identifier
  kms_key_id                    = aws_kms_key.kms[0].arn
}

resource "aws_db_instance" "db_instance" {
  max_allocated_storage     = var.max_allocated_storage
  character_set_name        = "AL32UTF8"
  instance_class            = var.instance_type
  db_name                   = "ORCL"
  identifier_prefix         = "db3dec"
  parameter_group_name      = aws_db_parameter_group.db_param_group.name
  engine                    = "oracle-se2-cdb"
  license_model             = var.license_type
  option_group_name         = "default:oracle-se2-cdb-19"
  port                      = "1521"
  multi_az                  = var.high_availability
  kms_key_id                = var.kms_key_id
  db_subnet_group_name      = aws_db_subnet_group.subnet_group.name
  vpc_security_group_ids    = [aws_security_group.db_security_group.id]
  storage_type              = var.storage_type
  snapshot_identifier       = local.final_snapshot_identifier
  publicly_accessible       = false
  delete_automated_backups  = var.delete_automated_backups
  deletion_protection       = !var.force_destroy
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "db3dec-final-snapshot"
  backup_retention_period   = var.backup_retention_period
  lifecycle {
    ignore_changes = [
      kms_key_id,
      snapshot_identifier,
      storage_encrypted,
      allocated_storage,
      max_allocated_storage,
      identifier,
      identifier_prefix,
      nchar_character_set_name,
      character_set_name,
      performance_insights_kms_key_id,
      identifier_prefix,
      identifier,
      restore_to_point_in_time,
      engine_version
    ]
  }
  timeouts {
    delete = "120m"
  }
}

resource "aws_db_parameter_group" "db_param_group" {
  name_prefix = "tdec"
  description = "Oracle Database Parameter Group"
  family      = "oracle-se2-cdb-19"

  parameter {
    name         = "processes"
    value        = "GREATEST({DBInstanceClassMemory/9868951}, 1000)"
    apply_method = "pending-reboot"
  }
}
