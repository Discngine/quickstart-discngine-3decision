# secrets Module - Output file for the vault module

output "jwt_public_key" {
  value = tls_private_key.jwt_key.public_key_pem
}

output "jwt_private_key" {
  value     = tls_private_key.jwt_key.private_key_pem
  sensitive = true
}

output "secrets_lambda_security_group_id" {
  value = aws_security_group.lambda_security_group.id
}

output "secrets_access_role_arn" {
  value = aws_iam_role.secrets_access_role.arn
}
