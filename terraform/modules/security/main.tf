# security Module - Main file for the vault module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

resource "aws_security_group_rule" "open_rds_access_from_eks" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 1521
  to_port                  = 1521
  source_security_group_id = var.node_security_group_id
  security_group_id        = var.db_security_group_id
}

resource "aws_security_group_rule" "add_db_to_security_eks" {
  type                     = "ingress"
  protocol                 = "-1"
  from_port                = 0
  to_port                  = 0
  source_security_group_id = var.db_security_group_id
  security_group_id        = var.node_security_group_id
}

resource "aws_security_group_rule" "allow_db_access_from_lambda" {
  type                     = "ingress"
  protocol                 = "tcp"
  from_port                = 1521
  to_port                  = 1521
  security_group_id        = var.db_security_group_id
  source_security_group_id = var.secrets_lambda_security_group_id
}
