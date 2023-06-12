# monitor Module - Output file for the monitor module

output "bucket_name" {
  value = aws_s3_bucket.bucket.bucket
}

output "redis_role_arn" {
  value = aws_iam_role.redis_role.arn
}
