# oke Module - Main file for the oke module

resource "aws_kms_key" "cluster_secrets_key" {
  count = var.create_cluster ? 1 : 0

  description         = "EKS cluster secrets key"
  enable_key_rotation = true
}

# Create EKS cluster
resource "aws_eks_cluster" "cluster" {
  count = var.create_cluster ? 1 : 0

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

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

data "aws_eks_cluster" "cluster" {
  count = var.create_cluster ? 0 : 1

  name = var.cluster_name
}

locals {
  cluster = var.create_cluster ? aws_eks_cluster.cluster[0] : data.aws_eks_cluster.cluster[0]
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

# Create security group for EKS cluster
resource "aws_security_group" "eks_cluster_sg" {
  count       = var.create_cluster ? 1 : 0
  name_prefix = "tdec-eks"
  description = "Security group for EKS cluster"

  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "eks_cluster_ingress" {
  count = var.create_cluster ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.eks_cluster_sg[0].id
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "eks_cluster_egress" {
  count = var.create_cluster ? 1 : 0

  type              = "egress"
  security_group_id = aws_security_group.eks_cluster_sg[0].id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_node_role" {
  count = var.create_node_group ? 1 : 0

  name_prefix = "3decision-eks-nodegroup"

  inline_policy {
    name = "RetrieveLicense"
    policy = jsonencode(
      {
        Version = "2012-10-17"
        Statement = [
          {
            Action   = ["s3:GetObject"]
            Effect   = "Allow"
            Resource = "arn:aws:s3:::dng-psilo-license/*"
          },
        ]
      }
    )
  }

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
  count = var.custom_ami == "" ? 1 : 0

  name = "/aws/service/eks/optimized-ami/${local.cluster.version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

locals {
  user_data = var.user_data != "" ? var.user_data : <<USERDATA
---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${local.cluster.name}
    apiServerEndpoint: ${local.cluster.endpoint}
    certificateAuthority: ${local.cluster.certificate_authority[0].data}
    cidr: ${local.cluster.kubernetes_network_config[0].service_ipv4_cidr}
USERDATA
}

resource "aws_launch_template" "EKSLaunchTemplate" {
  count = var.create_node_group ? 1 : 0

  image_id                = var.custom_ami != "" ? var.custom_ami : nonsensitive(data.aws_ssm_parameter.eks_ami_release_version[0].value)
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
  count = var.create_node_group ? 1 : 0

  cluster_name    = local.cluster.name
  node_group_name = "Default"
  node_role_arn   = aws_iam_role.eks_node_role[0].arn

  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 3
  }

  launch_template {
    id      = aws_launch_template.EKSLaunchTemplate[0].id
    version = aws_launch_template.EKSLaunchTemplate[0].latest_version
  }

  force_update_version = true
  subnet_ids           = var.private_subnet_ids
}

resource "aws_iam_openid_connect_provider" "default" {
  count = var.create_openid_provider ? 1 : 0

  url = local.cluster.identity.0.oidc.0.issuer

  client_id_list = [
    "sts.amazonaws.com",
    "sts.${var.region}.amazonaws.com"
  ]

  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

locals {
  openid_provider_arn = var.create_openid_provider ? aws_iam_openid_connect_provider.default[0].arn : var.openid_provider_arn
}

locals {
  oidc_issuer = element(split("https://", local.cluster.identity.0.oidc.0.issuer), 1)
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_csi_driver_role" {
  count = var.create_cluster ? 1 : 0

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
        "Federated": "${aws_iam_openid_connect_provider.default[0].arn}"
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
  count = var.create_cluster ? 1 : 0

  cluster_name             = local.cluster.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.eks_csi_driver_role[0].arn

  depends_on = [aws_eks_node_group.node_group]
}

resource "aws_eks_addon" "pia_addon" {
  count = var.add_pia_addon ? 1 : 0

  cluster_name = local.cluster.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.node_group]
}

# Create IAM PIA Role for license download

resource "aws_iam_role" "license_download" {
  count = var.use_pia ? 1 : 0

  name_prefix = "3decision-license-download"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "AllowEksAuthToAssumeRoleForPodIdentity",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "pods.eks.amazonaws.com"
          },
          "Action" : [
            "sts:AssumeRole",
            "sts:TagSession"
          ]
        }
      ]
    }
  )

  description = "Role designed to create Kubernetes secrets from Secrets Manager for 3decision quickstart"
}

resource "aws_eks_pod_identity_association" "license_download" {
  count = var.use_pia ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "tdecision"
  service_account = "tdecision-license-download"
  role_arn        = aws_iam_role.license_download[0].arn

  depends_on = [aws_eks_addon.pia_addon]
}

resource "aws_iam_policy" "license_download" {
  count = var.use_pia ? 1 : 0

  name_prefix = "3decision-license-download"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
        ],
        "Resource" : "arn:aws:s3:::dng-psilo-license/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "license_download" {
  count = var.use_pia ? 1 : 0

  role       = aws_iam_role.license_download[0].id
  policy_arn = aws_iam_policy.license_download[0].arn
}
