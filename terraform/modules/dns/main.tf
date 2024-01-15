# dns Module - Main file for the dns module
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

data "aws_lb" "ingress_load_balancer" {
  name = "lb-3dec"
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

resource "aws_route53_record" "tdec_reg_record" {
  zone_id = var.zone_id
  name    = "${var.registration_subdomain}.${var.domain}"
  type    = "A"
  alias {
    name                   = "dualstack.${data.aws_lb.ingress_load_balancer.dns_name}"
    zone_id                = data.aws_lb.ingress_load_balancer.zone_id
    evaluate_target_health = true
  }
}
