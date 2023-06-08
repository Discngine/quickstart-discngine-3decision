# oke Module - Output file for the oke module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

output "cluster_id" {
  value = aws_eks_cluster.cluster.id
}

output "cluster_name" {
  value = aws_eks_cluster.cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.cluster.endpoint
}

output "cluster_ca_cert" {
  value = aws_eks_cluster.cluster.certificate_authority.0.data
}

output "node_security_group_id" {
  value = aws_eks_cluster.cluster.vpc_config.0.cluster_security_group_id
}

output "oidc_issuer" {
  value = aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

output "openid_provider_arn" {
  value = aws_iam_openid_connect_provider.default.arn
}

output "service_cidr" {
  value = aws_eks_cluster.cluster.kubernetes_network_config.0.service_ipv4_cidr
}

output "node_group_role_arn" {
  value = aws_eks_node_group.node_group.node_role_arn
}
