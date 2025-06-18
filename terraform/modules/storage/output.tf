# monitor Module - Output file for the monitor module

output "bucket_name" {
  value = aws_s3_bucket.bucket.bucket
}

output "s3_role_arn" {
  value = try(aws_iam_role.role[0].arn, "")
}
