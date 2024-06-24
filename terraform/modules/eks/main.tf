# oke Module - Main file for the oke module

moved {
  from = aws_kms_key.cluster_secrets_key
  to   = aws_kms_key.cluster_secrets_key[0]
}

resource "aws_kms_key" "cluster_secrets_key" {
  count       = var.create_cluster ? 1 : 0
  description = "EKS cluster secrets key"
}

moved {
  from = aws_eks_cluster.cluster
  to   = aws_eks_cluster.cluster[0]
}

# Create EKS cluster
resource "aws_eks_cluster" "cluster" {
  count    = var.create_cluster ? 1 : 0
  name     = "EKS-tdecision"
  role_arn = aws_iam_role.eks_cluster_role[0].arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.k8s_public_access

    security_group_ids = [aws_security_group.eks_cluster_sg[0].id]
  }
  encryption_config {
    provider {
      key_arn = aws_kms_key.cluster_secrets_key[0].arn
    }
    resources = ["secrets"]
  }
}

data "aws_eks_cluster" "cluster" {
  count = var.create_cluster ? 0 : 1

  name = var.cluster_name
}

locals {
  cluster = var.create_cluster ? aws_eks_cluster.cluster : data.aws_eks_cluster.cluster
}

moved {
  from = aws_iam_role.eks_cluster_role
  to   = aws_iam_role.eks_cluster_role[0]
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster_role" {
  count       = var.create_cluster ? 1 : 0
  name_prefix = "3decision-eks-controlplane"

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
  assume_role_policy  = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

moved {
  from = aws_security_group.eks_cluster_sg
  to   = aws_security_group.eks_cluster_sg[0]
}

# Create security group for EKS cluster
resource "aws_security_group" "eks_cluster_sg" {
  count       = var.create_cluster ? 1 : 0
  name_prefix = "tdec-eks"
  description = "Security group for EKS cluster"

  vpc_id = var.vpc_id
}

moved {
  from = aws_security_group_rule.eks_cluster_ingress
  to   = aws_security_group_rule.eks_cluster_ingress[0]
}

resource "aws_security_group_rule" "eks_cluster_ingress" {
  count             = var.create_cluster ? 1 : 0
  type              = "ingress"
  security_group_id = aws_security_group.eks_cluster_sg[0].id
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

moved {
  from = aws_security_group_rule.eks_cluster_egress
  to   = aws_security_group_rule.eks_cluster_egress[0]
}

resource "aws_security_group_rule" "eks_cluster_egress" {
  count             = var.create_cluster ? 1 : 0
  type              = "egress"
  security_group_id = aws_security_group.eks_cluster_sg[0].id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_node_role" {
  name_prefix = "3decision-eks-nodegroup"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

data "aws_ssm_parameter" "eks_ami_release_version" {
  name = "/aws/service/eks/optimized-ami/${local.cluster.version}/amazon-linux-2/recommended/image_id"
}

locals {
  user_data = var.user_data != "" ? var.user_data : <<EOF
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh ${local.cluster.name} \
                  --b64-cluster-ca ${local.cluster.certificate_authority.0.data} \
                  --apiserver-endpoint ${local.cluster.endpoint} \
                  --use-max-pods false \
                  --kubelet-extra-args '--max-pods=110'
  EOF
}

resource "aws_launch_template" "EKSLaunchTemplate" {
  image_id                = var.custom_ami != "" ? var.custom_ami : nonsensitive(data.aws_ssm_parameter.eks_ami_release_version.value)
  instance_type           = var.instance_type
  disable_api_termination = true

  key_name = var.keypair_name
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.boot_volume_size
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  network_interfaces {
    associate_public_ip_address = false
  }

  user_data = base64encode(local.user_data)

  metadata_options {
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
    http_tokens                 = "required"
  }
}

# Create EKS node group
resource "aws_eks_node_group" "node_group" {
  cluster_name    = local.cluster.name
  node_group_name = "Default"
  node_role_arn   = aws_iam_role.eks_node_role.arn

  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }
  launch_template {
    id      = aws_launch_template.EKSLaunchTemplate.id
    version = aws_launch_template.EKSLaunchTemplate.latest_version
  }
  force_update_version = true
  subnet_ids           = var.private_subnet_ids
}

resource "aws_iam_openid_connect_provider" "default" {
  url = local.cluster.identity.0.oidc.0.issuer

  client_id_list = [
    "sts.amazonaws.com",
    "sts.${var.region}.amazonaws.com"
  ]

  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

locals {
  oidc_issuer = element(split("https://", local.cluster.identity.0.oidc.0.issuer), 1)
}

moved {
  from = aws_iam_role.eks_csi_driver_role
  to   = aws_iam_role.eks_csi_driver_role[0]
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_csi_driver_role" {
  count       = var.create_cluster ? 1 : 0
  name_prefix = "3decision-csi-driver"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${aws_iam_openid_connect_provider.default.arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${local.oidc_issuer}:aud": "sts.amazonaws.com",
          "${local.oidc_issuer}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF
  inline_policy {
    name = "AmazonEbsCsiDeviceEncryption"
    policy = jsonencode(
      {
        Version = "2012-10-17"
        Statement = [
          {
            Action   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
            Effect   = "Allow"
            Resource = "arn:aws:kms:${var.region}:${var.account_id}:key/*"
          },
          {
            Action = [
              "kms:Decrypt",
              "kms:DescribeKey",
              "kms:Encrypt",
              "kms:GenerateDataKey",
              "kms:GenerateDataKeyWithoutPlaintext",
              "kms:GenerateDataKeyPair",
              "kms:GenerateDataKeyPairWithoutPlaintext",
              "kms:ReEncryptFrom",
              "kms:ReEncryptTo",
            ]
            Effect   = "Allow"
            Resource = "arn:aws:kms:${var.region}:${var.account_id}:key/*"
          }
        ]
      }
    )
  }
}

moved {
  from = aws_eks_addon.csi_driver
  to   = aws_eks_addon.csi_driver[0]
}

resource "aws_eks_addon" "csi_driver" {
  count = var.create_cluster ? 1 : 0

  cluster_name             = local.cluster.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.eks_csi_driver_role[0].arn

  depends_on = [aws_eks_node_group.node_group]
}
