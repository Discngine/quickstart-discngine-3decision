# storage Module - Main file for the storage module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

locals {
  oidc_issuer = element(split("https://", var.eks_oidc_issuer), 1)
}

resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "tdec"
  force_destroy = false##var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "example" {
  bucket = aws_s3_bucket.bucket.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.bucket_ownership]
}

resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowPublicAccess",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "*",
        "Resource": [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ],
        "Condition": {
          "StringEquals": {
            "s3:DataAccessPointAccount": var.account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket.bucket]
}

resource "aws_s3_access_point" "redis_access_point" {
  name   = "3decision-redis-access-point"
  bucket = aws_s3_bucket.bucket.id

  vpc_configuration {
    vpc_id = var.vpc_id
  }

  public_access_block_configuration {
    block_public_acls       = true
    ignore_public_acls      = true
    block_public_policy     = true
    restrict_public_buckets = true
  }
}

resource "aws_iam_role" "redis_role" {
  name               = "3decision-redis-s3-eu-central-1"
  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_issuer}"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringLike": {
            "${local.oidc_issuer}:sub": "system:serviceaccount:*:redis-s3-upload"
          }
        }
      }
    ]
  })

  description = "Role designed to access the Redis access point inside EKS pods"
}

resource "aws_iam_policy" "redis_policy" {
  name   = "3decision-redis-s3-eu-central-1"
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        "Resource": [
          aws_s3_access_point.redis_access_point.arn,
          "${aws_s3_access_point.redis_access_point.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secret_rotator_lambda_role_policy_attachment" {
  role       = aws_iam_role.redis_role.id
  policy_arn = aws_iam_policy.redis_policy.arn
}
