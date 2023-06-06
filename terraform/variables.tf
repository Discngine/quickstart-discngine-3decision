## Copyright © 2020, Oracle and/or its affiliates.
## All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

variable "tdecision_namespace" {
  default = "tdecision"
  description = "namespace in which to deploy the main 3decision application"
}

variable "cert_manager_chart" {
  description = "A map with information about the cert manager helm chart"

  type = object({
    name             = optional(string, "cert-manager")
    repository       = optional(string, "https://charts.jetstack.io")
    chart            = optional(string, "cert-manager")
    namespace        = optional(string, "cert-manager")
    create_namespace = optional(bool, true)
    version          = optional(string, "1.8.0")
  })
  default = {}
}

variable "external_secrets_chart" {
  description = "A map with information about the external secrets operator helm chart"

  type = object({
    name             = optional(string, "external-secrets")
    repository       = optional(string, "https://charts.external-secrets.io")
    chart            = optional(string, "external-secrets")
    namespace        = optional(string, "external-secrets")
    create_namespace = optional(bool, true)
  })
  default = {}
}

variable "reloader_chart" {
  description = "A map with information about the nginx controller helm chart"

  type = object({
    name             = optional(string, "reloader")
    repository       = optional(string, "https://stakater.github.io/stakater-charts")
    chart            = optional(string, "reloader")
    namespace        = optional(string, "reloader")
    create_namespace = optional(bool, true)
  })
  default = {}
}

variable "redis_sentinel_chart" {
  description = "A map with information about the redis sentinel helm chart"

  type = object({
    name             = optional(string, "sentinel")
    chart            = optional(string, "oci://fra.ocir.io/discngine1/3decision_kube/redis-sentinel")
    namespace        = optional(string, "redis-cluster")
    create_namespace = optional(bool, true)
    version          = optional(string, "16.3.1")
  })
  default = {}
}

variable "okta_oidc" {
  default = {
    client_id = "none"
    domain    = ""
    server_id = ""
    secret    = ""
  }
  description = "Okta Client ID for OKTA integration"
  sensitive   = true
}

variable "azure_oidc" {
  description = "Azure Client ID for authentication in application"
  default = {
    client_id = "none"
    tenant    = ""
    secret    = ""
  }
  sensitive = true
}

variable "google_oidc" {
  description = "Google Client ID for authentication in application"
  default = {
    client_id = "none"
    secret    = ""
  }
  sensitive = true
}
