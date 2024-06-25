# oke Module - Output file for the oke module

output "cluster_id" {
  value = local.cluster.id
}

output "cluster_name" {
  value = local.cluster.name
}

output "cluster_endpoint" {
  value = local.cluster.endpoint
}

output "cluster_ca_cert" {
  value = local.cluster.certificate_authority.0.data
}

output "node_security_group_id" {
  value = local.cluster.vpc_config.0.cluster_security_group_id
}

output "oidc_issuer" {
  value = local.cluster.identity.0.oidc.0.issuer
}

output "openid_provider_arn" {
  value = local.openid_provider_arn
}

output "service_cidr" {
  value = local.cluster.kubernetes_network_config.0.service_ipv4_cidr
}

output "node_group_role_arn" {
  value = aws_eks_node_group.node_group.node_role_arn
}
