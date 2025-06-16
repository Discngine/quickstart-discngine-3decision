# secrets Module - Main file for the vault module

terraform {
  required_providers {
    tls = {
      source = "hashicorp/tls"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

resource "tls_private_key" "jwt_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#########
# LAMBDA FUNCTION
#########

resource "aws_security_group" "lambda_security_group" {
  name_prefix = "tdec-secrets-sg"
  description = "Creates lambda security group to access the database"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "lambda_security_group_egress" {
  type              = "egress"
  security_group_id = aws_security_group.lambda_security_group.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_s3_bucket" "lambda_sources" {
  force_destroy = "true"
}

# Upload an object
resource "aws_s3_object" "object" {
  bucket      = aws_s3_bucket.lambda_sources.id
  key         = "package.zip"
  source      = "${path.root}/function/package.zip"
  source_hash = filemd5("${path.root}/function/package.zip")
}

# This is created to prevent the fact that the lambda resource sometimes randomly fails with error
# InsufficientRolePermissions: The function's execution role doesn't have permission to perform this operation
resource "time_sleep" "wait_1_minute" {
  depends_on = [
    aws_iam_role_policy_attachment.secret_rotator_lambda_role_policy_attachment
  ]
  create_duration = "1m"

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_lambda_function" "secret_rotator_lambda" {
  function_name = "3decision-rotator-lambda"

  role = aws_iam_role.secret_rotator_lambda_role.arn

  handler          = "lambda_function.lambda_handler"
  s3_bucket        = aws_s3_bucket.lambda_sources.id
  s3_key           = aws_s3_object.object.id
  source_code_hash = filebase64sha256("${path.root}/function/package.zip")

  runtime = "python3.9"
  timeout = 30

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.region}.amazonaws.com",
      EXCLUDE_CHARACTERS       = "' ! \" # $ % & ( ) * + , - . / : ; < = > ? @ [ \\ ] ^ ` { | } ~"
    }
  }

  vpc_config {
    security_group_ids = [aws_security_group.lambda_security_group.id]
    subnet_ids         = var.private_subnet_ids
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
      echo "detaching security group"
      aws lambda update-function-configuration --function-name ${self.function_name} --vpc-config '{"SubnetIds": [], "SecurityGroupIds": []}' &&
      while result=$(aws ec2 describe-network-interfaces --output text --filters '[{"Name": "group-id", "Values": ["${self.tags.security_group_id}"] }, {"Name": "status", "Values": ["in-use", "available"]}]'); test "$result" != ""; do
        sleep 10;
      done
      echo "successfully detached security group"
    EOF
  }

  tags = {
    security_group_id = aws_security_group.lambda_security_group.id
  }

  depends_on = [
    aws_iam_role_policy_attachment.secret_rotator_lambda_role_policy_attachment,
    time_sleep.wait_1_minute
  ]
}

resource "aws_lambda_permission" "allow_secret_manager_call_lambda" {
  function_name  = aws_lambda_function.secret_rotator_lambda.function_name
  statement_id   = "AllowExecutionSecretManager"
  action         = "lambda:InvokeFunction"
  principal      = "secretsmanager.amazonaws.com"
  source_account = var.account_id
}

resource "aws_iam_role" "secret_rotator_lambda_role" {
  name_prefix = "3decision-rotator-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "secret_rotator_lambda_policy" {
  name_prefix = "3decision-rotator-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ],
        Resource = [for secret in aws_secretsmanager_secret.db_passwords : secret.arn]
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetRandomPassword"
        ],
        Resource = "*"
      },
      {
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:DetachNetworkInterface"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
      {
        Effect   = "Allow",
        Action   = "logs:CreateLogGroup",
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/3decision-rotator-lambda:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secret_rotator_lambda_role_policy_attachment" {
  role       = aws_iam_role.secret_rotator_lambda_role.id
  policy_arn = aws_iam_policy.secret_rotator_lambda_policy.arn
}


resource "aws_secretsmanager_secret" "db_passwords" {
  for_each = toset(["ADMIN", "PD_T1_DNG_THREEDECISION", "CHEMBL_29"])

  name                    = "3dec-${lower(each.key)}-db"
  recovery_window_in_days = 0

  tags = {
    "Name" = each.key
  }
}

resource "aws_secretsmanager_secret_version" "db_passwords_version" {
  for_each = toset(["ADMIN", "PD_T1_DNG_THREEDECISION", "CHEMBL_29"])

  secret_id = aws_secretsmanager_secret.db_passwords[each.key].id
  secret_string = jsonencode(
    {
      username = each.key
      password = var.initial_db_passwords[each.key]
      engine   = "oracle"
      host     = element(split(":", var.db_endpoint), 0)
      dbname   = var.db_name
    }
  )
}

resource "aws_secretsmanager_secret_rotation" "db_master_password_rotation" {
  for_each = toset(var.enable_db_user_rotation ? ["ADMIN", "PD_T1_DNG_THREEDECISION", "CHEMBL_29"] : [])

  secret_id           = aws_secretsmanager_secret.db_passwords[each.key].id
  rotation_lambda_arn = aws_lambda_function.secret_rotator_lambda.arn

  rotation_rules {
    # Run on the first sunday of the month at 2 AM
    schedule_expression = each.key == "ADMIN" ? var.db_admin_rotation_schedule : var.db_user_rotation_schedule
  }
  depends_on = [aws_secretsmanager_secret_version.db_passwords_version]
}

resource "aws_iam_role" "secrets_access_role" {
  name_prefix = "3decision-database-secrets"
  assume_role_policy = var.external_secrets_pia ? jsonencode(
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
    ) : jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : ["${var.node_group_role_arn}"]
          },
          "Action" : ["sts:AssumeRole"]
        }
      ]
    }
  )

  description = "Role designed to create Kubernetes secrets from Secrets Manager for 3decision quickstart"
}

resource "aws_eks_pod_identity_association" "pod_identity_association" {
  count = var.external_secrets_pia ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.secrets_access_role.arn
}

resource "aws_iam_policy" "secrets_access_policy" {
  name_prefix = "3decision-database-secrets"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ],
        "Resource" : [
          for secret in aws_secretsmanager_secret.db_passwords : secret.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access" {
  role       = aws_iam_role.secrets_access_role.id
  policy_arn = aws_iam_policy.secrets_access_policy.arn
}
