# oke Module - Output file for the oke module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

output "eks_cluster_name" {
  value = aws_eks_cluster.cluster.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.cluster.endpoint
}

output "node_security_group_id" {
  value = aws_security_group.eks_cluster_sg.id
}

output eks_oidc_issuer {
  value = aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}