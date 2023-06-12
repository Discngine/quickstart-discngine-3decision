# monitor Module - Output file for the monitor module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

output "bucket_name" {
  value = aws_s3_bucket.bucket.bucket
}

output "redis_role_arn" {
  value = aws_iam_role.redis_role.arn
}
