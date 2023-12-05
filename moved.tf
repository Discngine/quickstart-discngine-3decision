# File containing moved blocks

moved {
  from = module.storage.aws_iam_role.redis_role
  to   = module.storage["redis"].aws_iam_role.role
}

moved {
  from = module.storage.aws_iam_role_policy_attachment.secret_rotator_lambda_role_policy_attachment
  to   = module.storage["redis"].aws_iam_role_policy_attachment.policy_attachment
}

moved {
  from = module.storage.aws_iam_policy.redis_policy
  to   = module.storage["redis"].aws_iam_policy.policy
}

moved {
  from = module.storage.aws_s3_bucket.bucket
  to   = module.storage["redis"].aws_s3_bucket.bucket
}

moved {
  from = module.storage.aws_s3_bucket_ownership_controls.bucket_ownership
  to   = module.storage["redis"].aws_s3_bucket_ownership_controls.bucket_ownership
}

moved {
  from = module.storage.aws_s3_bucket_public_access_block.public_access_block
  to   = module.storage["redis"].aws_s3_bucket_public_access_block.public_access_block
}