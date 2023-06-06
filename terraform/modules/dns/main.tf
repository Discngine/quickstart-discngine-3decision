# dns Module - Main file for the dns module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

locals {
  ingress_svc_name      = "ingress-nginx-controller"
  ingress_svc_namespace = "ingress-nginx"
  ingress_load_balancer_tags = {
    "service.k8s.aws/resource" = "LoadBalancer"
    "service.k8s.aws/stack"    = "${local.ingress_svc_namespace}/${local.ingress_svc_name}"
    "elbv2.k8s.aws/cluster"    = var.cluster_id
  }
}

data "aws_lb" "ingress_load_balancer" {
  tags = local.ingress_load_balancer_tags
}

resource "aws_route53_record" "tdec_record" {
  zone_id = "Z0993829VKYUI0DM32P4"
  name    = "3decision.discngine.io"
  type    = "A"
  alias {
    name                   = "dualstack.${data.aws_lb.ingress_load_balancer.dns_name}"
    zone_id                = data.aws_lb.ingress_load_balancer.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "tdec_api_record" {
  zone_id = "Z0993829VKYUI0DM32P4"
  name    = "3decision-api.discngine.io"
  type    = "A"
  alias {
    name                   = "dualstack.${data.aws_lb.ingress_load_balancer.dns_name}"
    zone_id                = data.aws_lb.ingress_load_balancer.zone_id
    evaluate_target_health = true
  }
}
