# database Module - Main file for the database module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

resource "aws_kms_key" "encryption_key" {
  enable_key_rotation = true

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "${terraform.workspace}",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${var.account_id}"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncryptTo",
        "kms:ReEncryptFrom",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyPairWithoutPlaintext",
        "kms:GenerateDataKeyPair",
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:CallerAccount": "${var.account_id}",
          "kms:ViaService": "rds.${var.region}.amazonaws.com"
        }
      }
    }
  ]
}
EOF
}

resource "aws_kms_alias" "encryption_key_alias" {
  name_prefix   = "alias/tdec"
  target_key_id = aws_kms_key.encryption_key.key_id
}

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

resource "aws_db_instance" "db_instance" {
  allocated_storage         = 500
  max_allocated_storage     = 1000
  character_set_name        = "AL32UTF8"
  instance_class            = var.instance_type
  db_name                   = "ORCL"
  identifier_prefix         = "db3dec"
  parameter_group_name      = aws_db_parameter_group.db_param_group.name
  engine                    = "oracle-se2-cdb"
  engine_version            = "19.0.0.0.ru-2023-04.rur-2023-04.r1"
  license_model             = var.license_type
  option_group_name         = "default:oracle-se2-cdb-19"
  port                      = "1521"
  multi_az                  = var.high_availability
  kms_key_id                = aws_kms_key.encryption_key.arn
  db_subnet_group_name      = aws_db_subnet_group.subnet_group.name
  vpc_security_group_ids    = [aws_security_group.db_security_group.id]
  storage_type              = "gp2"
  snapshot_identifier       = var.snapshot_identifier != null ? var.snapshot_identifier : "arn:aws:rds:${var.region}:751149478800:snapshot:db3dec"
  publicly_accessible       = false
  deletion_protection       = !var.force_destroy
  skip_final_snapshot       = false
  final_snapshot_identifier = "db3dec-final-snapshot"
  backup_retention_period   = var.backup_retention_period
  lifecycle {
    ignore_changes = [kms_key_id, snapshot_identifier]
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
