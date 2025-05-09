resource "random_uuid" "bucket_suffix" {}

locals {
  bucket_suffix = substr(random_uuid.bucket_suffix.result, 0, 8)
  bucket_name   = "3decision-db-migration-${local.bucket_suffix}"
}

resource "aws_s3_bucket" "rds_data" {
  count  = var.db_migration ? 1 : 0
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "rds_data_block" {
  count  = var.db_migration ? 1 : 0
  bucket = aws_s3_bucket.rds_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "rds_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "rds_s3_policy" {
  count = var.db_migration ? 1 : 0

  name = "3decision-migration-rds-s3-access-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:s3:::${local.bucket_name}",
          "arn:aws:s3:::${local.bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "rds_s3_role" {
  count              = var.db_migration ? 1 : 0
  name               = "3decision-migration-rds-s3-access-role"
  assume_role_policy = data.aws_iam_policy_document.rds_assume_role.json
}

resource "aws_iam_role_policy_attachment" "rds_s3_attach" {
  count = var.db_migration ? 1 : 0

  role       = aws_iam_role.rds_s3_role[0].name
  policy_arn = aws_iam_policy.rds_s3_policy[0].arn
}

resource "aws_db_option_group" "s3_option_group" {
  count = var.db_migration ? 1 : 0

  name                 = "rds-s3-option-group"
  engine_name          = "oracle-se2-cdb"
  major_engine_version = "19"

  option {
    option_name = "S3_INTEGRATION"
  }

  tags = {
    Name = "s3-option-group"
  }
}

resource "aws_db_instance_role_association" "s3_integration" {
  count                  = var.db_migration ? 1 : 0
  db_instance_identifier = aws_db_instance.db_instance.identifier
  feature_name           = "S3_INTEGRATION"
  role_arn               = aws_iam_role.rds_s3_role[0].arn
}
