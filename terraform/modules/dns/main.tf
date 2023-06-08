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

data "aws_lb" "ingress_load_balancer" {
  name = "lb3dec"
}

resource "aws_route53_record" "tdec_record" {
  zone_id = var.zone_id
  name    = "${var.main_subdomain}.${var.domain}"
  type    = "A"
  alias {
    name                   = "dualstack.${data.aws_lb.ingress_load_balancer.dns_name}"
    zone_id                = data.aws_lb.ingress_load_balancer.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "tdec_api_record" {
  zone_id = var.zone_id
  name    = "${var.api_subdomain}.${var.domain}"
  type    = "A"
  alias {
    name                   = "dualstack.${data.aws_lb.ingress_load_balancer.dns_name}"
    zone_id                = data.aws_lb.ingress_load_balancer.zone_id
    evaluate_target_health = true
  }
}
