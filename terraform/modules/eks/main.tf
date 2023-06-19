# oke Module - Main file for the oke module

resource "aws_kms_key" "cluster_secrets_key" {
  description = "EKS cluster secrets key"
}

# Create EKS cluster
resource "aws_eks_cluster" "cluster" {
  name     = "EKS-tdecision"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.k8s_public_access

    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }
  encryption_config {
    provider {
      key_arn = aws_kms_key.cluster_secrets_key.arn
    }
    resources = ["secrets"]
  }
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster_role" {
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

# Create security group for EKS cluster
resource "aws_security_group" "eks_cluster_sg" {
  name_prefix = "tdec-eks"
  description = "Security group for EKS cluster"

  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "eks_cluster_ingress" {
  type              = "ingress"
  security_group_id = aws_security_group.eks_cluster_sg.id
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]
}

resource "aws_security_group_rule" "eks_cluster_egress" {
  type              = "egress"
  security_group_id = aws_security_group.eks_cluster_sg.id
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
  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.cluster.version}/amazon-linux-2/recommended/image_id"
}

locals {
  user_data = <<EOF
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh ${aws_eks_cluster.cluster.name} \
                  --b64-cluster-ca ${aws_eks_cluster.cluster.certificate_authority.0.data} \
                  --apiserver-endpoint ${aws_eks_cluster.cluster.endpoint} \
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
  cluster_name    = aws_eks_cluster.cluster.name
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

  subnet_ids = var.private_subnet_ids
}

resource "aws_iam_openid_connect_provider" "default" {
  url = aws_eks_cluster.cluster.identity.0.oidc.0.issuer

  client_id_list = [
    "sts.amazonaws.com",
    "sts.${var.region}.amazonaws.com"
  ]

  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

locals {
  oidc_issuer = element(split("https://", aws_eks_cluster.cluster.identity.0.oidc.0.issuer), 1)
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_csi_driver_role" {
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

resource "aws_eks_addon" "csi_driver" {
  cluster_name             = aws_eks_cluster.cluster.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.eks_csi_driver_role.arn

  depends_on = [aws_eks_node_group.node_group]
}
