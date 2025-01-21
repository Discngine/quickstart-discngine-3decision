# Main - Modules instantion

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    key                  = "terraform.state"
    workspace_key_prefix = "3decision-quickstart"
    encrypt              = "true"
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = var.default_tags
  }
}

resource "aws_iam_policy" "kms_policy" {
  name        = "kms-policy"
  description = "IAM policy for KMS permissions"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource = "arn:aws:kms:us-east-1:423070877037:key/*",
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "arn:aws:kms:us-east-1:423070877037:key/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kms_policy_attachment" {
  role       = "AmazonEKS_EBS_CSI_DriverRole"
  policy_arn = aws_iam_policy.kms_policy.arn
}
