# Data Migration Module - Outputs

output "rds_s3_role_arn" {
  description = "IAM role ARN for RDS S3 integration - provide this to Discngine for bucket policy"
  value       = var.run_data_migration ? aws_iam_role.rds_s3[0].arn : null
}

output "bucket_policy_statement" {
  description = "JSON statement to add to dng-psilo-license bucket policy (provide to Discngine)"
  value = var.run_data_migration ? jsonencode({
    Sid    = "AllowRDSAccess"
    Effect = "Allow"
    Principal = {
      AWS = aws_iam_role.rds_s3[0].arn
    }
    Action   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    Resource = ["arn:aws:s3:::dng-psilo-license", "arn:aws:s3:::dng-psilo-license/*"]
  }) : null
}

output "job_name" {
  description = "Migration job name"
  value       = var.run_data_migration ? "data-migration" : null
}

output "status_command" {
  description = "Command to check migration status"
  value       = var.run_data_migration ? "kubectl get job data-migration -n tdecision" : null
}

output "logs_command" {
  description = "Command to view migration logs"
  value       = var.run_data_migration ? "kubectl logs -n tdecision job/data-migration -f" : null
}
