locals {
  cev_bucket_name   = "test-cev"
}

resource "aws_kms_key" "rds_custom_kms" {
  description = "KMS key for RDS Custom for Oracle"
}

resource "aws_rds_custom_db_engine_version" "oracle_cev" {
  engine                                     = "custom-oracle-se2-cdb"
  engine_version                             = "19.cdb_cev1"
  database_installation_files_s3_bucket_name = local.cev_bucket_name
  kms_key_id                                 = aws_kms_key.rds_custom_kms.arn
  manifest = jsonencode({
    mediaImportTemplateVersion    = "2020-08-14"
    databaseInstallationFileNames = ["V982063-01.zip"]
    installationParameters = {
      oracleHome    = "/rdsdbbin/oracle.19.custom.r1.SE2-CDB.1"
      oracleBase    = "/rdsdbbin"
      unixUid       = 61001
      unixUname     = "rdsdb"
      unixGroupId   = 1000
      unixGroupName = "rdsdb"
    }
  })
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_"
}

resource "aws_db_instance" "rds_custom_oracle" {
  auto_minor_version_upgrade  = false
  engine                      = aws_rds_custom_db_engine_version.oracle_cev.engine
  engine_version              = aws_rds_custom_db_engine_version.oracle_cev.engine_version
  kms_key_id                  = aws_kms_key.rds_custom_kms.arn
  custom_iam_instance_profile = aws_iam_instance_profile.rds_custom_instance_profile.name
  username = "ADMIN"
  password = random_password.password.result
  allocated_storage = 500
  max_allocated_storage       = 1000
  instance_class              = var.instance_type
  db_name                     = "ORCL"
  identifier_prefix           = "db3dec"
  license_model               = var.license_type
  port                        = "1521"
  db_subnet_group_name        = aws_db_subnet_group.subnet_group.name
  vpc_security_group_ids      = [aws_security_group.db_security_group.id]
  storage_type                = "gp2"
  publicly_accessible         = false
  delete_automated_backups    = var.delete_automated_backups
  deletion_protection         = !var.force_destroy
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = "db3dec-final-snapshot"
  backup_retention_period     = min(max(var.backup_retention_period, 1), 354) 
  storage_encrypted = true
  lifecycle {
    ignore_changes = [
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
    create = "3h"
    delete = "3h"
    update = "3h"
  }
}

resource "aws_iam_role" "rds_custom_role" {
  name_prefix = "AWSRDSCustom-3decision-rds-custom-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_custom_managed_policy_attachment" {
  role       = aws_iam_role.rds_custom_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSCustomInstanceProfileRolePolicy"
}

resource "aws_iam_instance_profile" "rds_custom_instance_profile" {
  name_prefix = "AWSRDSCustom-3decision-rds-custom-role"
  role        = aws_iam_role.rds_custom_role.name
}

resource "aws_iam_policy" "rds_custom_policy" {
  name        = "AWSRDSCustom-3decision-rds-custom-policy"
  description = "Policy for RDS Custom instance"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:DescribeAssociation",
          "ssm:DescribeDocument",
          "ssm:GetConnectionStatus",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetParameters",
          "ssm:ListInstanceAssociations",
          "ssm:GetParameter",
          "ssm:UpdateAssociationStatus",
          "ssmmessages:CreateDataChannel",
          "ssm:PutInventory",
          "ssm:UpdateInstanceInformation",
          "ssm:DescribeInstanceInformation",
          "ssmmessages:OpenDataChannel",
          "ssm:GetDocument",
          "ssm:ListAssociations",
          "ssm:PutComplianceItems",
          "ssm:UpdateInstanceAssociationStatus"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:PutLogEvents",
          "logs:CreateLogGroup"
        ],
        Resource = "arn:aws:logs:eu-central-1:${var.account_id}:log-group:rds-custom-instance*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:getObjectVersion",
          "s3:getObject",
          "s3:putObject"
        ],
        Resource = "arn:aws:s3:::do-not-delete-rds-custom-*/*"
      },
      {
        Effect = "Allow",
        Action = [
          "events:PutEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = "arn:aws:secretsmanager:eu-central-1:${var.account_id}:secret:do-not-delete-rds-custom-*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucketVersions"
        ],
        Resource = "arn:aws:s3:::do-not-delete-rds-custom-*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateSnapshots"
        ],
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:volume/*"
        ],
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/AWSRDSCustom" = "custom-oracle"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateSnapshots"
        ],
        Resource = "arn:aws:ec2::*:snapshot/*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:CreateTags"
        ],
        Resource = "*",
        Condition = {
          StringLike = {
            "ec2:CreateAction" = "CreateSnapshots"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource = "arn:aws:kms:eu-central-1:${var.account_id}:key/${aws_kms_key.rds_custom_kms.id}"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "rds_custom_policy_attachment" {
  role       = aws_iam_role.rds_custom_role.name
  policy_arn = aws_iam_policy.rds_custom_policy.arn
}
