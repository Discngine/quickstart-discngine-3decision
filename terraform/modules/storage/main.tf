# storage Module - Main file for the storage module

locals {
  oidc_issuer = element(split("https://", var.eks_oidc_issuer), 1)
}

resource "aws_s3_bucket" "bucket" {
  bucket_prefix = "tdec-${var.name}"
  force_destroy = var.force_destroy

  lifecycle {
    ignore_changes = [bucket_prefix]
  }
}

resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_bucket_lifecycle" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    id     = "IntelligentTiering"
    status = "Enabled"
    transition {
      days          = "0"
      storage_class = "INTELLIGENT_TIERING"
    }
    filter {
      object_size_greater_than = "128000"
    }
  }
}

resource "aws_iam_role" "role" {
  name_prefix = "3decision-${var.name}-s3"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "${var.openid_provider_arn}"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringLike" : {
            "${local.oidc_issuer}:sub" : var.allowed_service_accounts
          }
        }
      }
    ]
  })

  description = "Role designed to access the access point inside EKS pods"
}


resource "aws_iam_policy" "policy" {
  name_prefix = "3decision-${var.name}-s3"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        "Resource" : [
          "${aws_s3_bucket.bucket.arn}",
          "${aws_s3_bucket.bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.role.id
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_s3_bucket_policy" "enforce_ssl" {
  bucket = aws_s3_bucket.bucket.id

  policy = jsonencode({
    Id = "ExamplePolicy"
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowSSLRequestsOnly"
        Action = "s3:*"
        Effect = "Deny"
        Resource = [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
        Principal = "*"
      }
    ]
  })
}
