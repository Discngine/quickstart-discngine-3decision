# kubernetes Module - Main file for the kubernetes module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

###################
#    Manifests
###################

terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
}

resource "kubernetes_namespace" "tdec_namespace" {
  metadata {
    name = var.tdecision_namespace
  }
}

resource "kubernetes_namespace" "redis_namespace" {
  metadata {
    name = "redis-cluster"
  }
}

resource "kubernetes_namespace" "choral_namespace" {
  metadata {
    name = "choral"
  }
}

resource "kubernetes_namespace" "tools_namespace" {
  metadata {
    name = "tools"
  }
}

resource "kubectl_manifest" "sqlcl" {
  yaml_body  = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sqlcl
  namespace: tools
  labels:
    role: help
    app: sqlcl
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sqlcl
  template:
    metadata:
      name: sqlcl
      namespace: tools
      labels:
        role: help
        app: sqlcl
    spec:
      containers:
        - name: web
          image: fra.ocir.io/discngine1/3decision_kube/sqlcl:latest
          command: [ "/bin/bash", "-c", "--" ]
          envFrom:
          - secretRef:
              name: database-secrets
          env:
            - name: CONNECTION_STRING
              value: ${var.connection_string}
            - name: sq3
              value: /root/sqlcl/bin/sql PD_T1_DNG_THREEDECISION/$${DB_PASSWD}@$${CONNECTION_STRING}
            - name: sqc
              value: /root/sqlcl/bin/sql CHEMBL_23/$${CHEMBL_DB_PASSWD}@$${CONNECTION_STRING}
            - name: sqs
              value: /root/sqlcl/bin/sql SYS/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} as sysdba
          args: [ "sleep infinity" ]
  YAML
  depends_on = [kubernetes_namespace.tools_namespace]
}

resource "kubernetes_secret" "jwt_secret" {
  metadata {
    name      = var.jwt_secret_name
    namespace = var.tdecision_namespace
  }

  data = {
    "id_rsa"     = var.jwt_ssh_private
    "id_rsa.pub" = var.jwt_ssh_public
  }
  depends_on = [kubernetes_namespace.tdec_namespace]
}

resource "kubernetes_secret" "bucket_access" {
  metadata {
    name      = "bucket-access"
    namespace = var.tdecision_namespace
  }
  data = {
    bucketName = var.bucket_name
    namespace  = var.namespace
  }
  depends_on = [kubernetes_namespace.tdec_namespace]
}

resource "kubectl_manifest" "secretstore" {
  yaml_body  = <<YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: oci-secret-store
      namespace: external-secrets
    spec:
      provider:
  YAML
  depends_on = [helm_release.external_secrets_chart]
}

resource "kubectl_manifest" "ClusterExternalSecret" {
  yaml_body  = <<YAML
apiVersion: external-secrets.io/v1beta1
kind: ClusterExternalSecret
metadata:
  name: database-secrets
  namespace: external-secrets
spec:
  externalSecretName: database-secrets
  namespaceSelector:
    matchExpressions:
      - {key: kubernetes.io/metadata.name, operator: In, values: [${var.tdecision_namespace}, choral, tools]}
  refreshTime: "1m"
  externalSecretSpec:
    secretStoreRef:
      name: oci-secret-store
      kind: ClusterSecretStore
    refreshInterval: "1m"
    target:
      name: database-secrets
      creationPolicy: Owner
    data:
      - secretKey: SYS_DB_PASSWD
        remoteRef:
          key: sys_passwd_${var.name_resources}${var.secret_names_suffix}
      - secretKey: ORACLE_PASSWORD
        remoteRef:
          key: tdec_passwd_${var.name_resources}${var.secret_names_suffix}
      - secretKey: DB_PASSWD
        remoteRef:
          key: tdec_passwd_${var.name_resources}${var.secret_names_suffix}
      - secretKey: CHEMBL_DB_PASSWD
        remoteRef:
          key: chembl_passwd_${var.name_resources}${var.secret_names_suffix}
      - secretKey: CHORAL_DB_PASSWD
        remoteRef:
          key: choral_passwd_${var.name_resources}${var.secret_names_suffix}
  YAML
  depends_on = [helm_release.external_secrets_chart]
}

resource "kubernetes_secret" "nest-authentication-secrets" {
  metadata {
    name      = "nest-authentication-secrets"
    namespace = var.tdecision_namespace
  }
  data = {
    AZURE_TENANT     = var.azure_oidc.tenant
    AZURE_SECRET     = var.azure_oidc.secret
    GOOGLE_SECRET    = var.google_oidc.secret
    AZUREBTOC_TENANT = var.azurebtc_oidc.tenant
    AZUREBTOC_SECRET = var.azurebtc_oidc.secret
    AZUREBTOC_POLICY = var.azurebtc_oidc.policy
    OKTA_DOMAIN      = var.okta_oidc.domain
    OKTA_SERVER_ID   = var.okta_oidc.server_id
    OKTA_SECRET      = var.okta_oidc.secret
  }
  depends_on = [kubernetes_namespace.tdec_namespace]
}

resource "kubectl_manifest" "sentinel_configmap_redis" {
  yaml_body  = <<YAML
---
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${var.redis_sentinel_chart.namespace}
  name: sentinel-backup-env-cm
data:
  BUCKET_NAME: ${var.bucket_name}
  PROVIDER: aws
  OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING: "True"
  YAML
  depends_on = [kubernetes_namespace.redis_namespace]
}

locals {
  values_config = <<EOT
      commonConfiguration: |-
        # Enable AOF https://redis.io/topics/persistence#append-only-file
        appendonly no
        # Disable RDB persistence, AOF persistence already enabled.
        save 300 1
      sentinel:
        enabled: true
        resources:
          requests:
            cpu: 100m
            memory: 500Mi
      master:
        service:
          ports:
            redis: 6380
      replica:
        resources:
          requests:
            cpu: 500m
            memory: 2Gi
        extraVolumes:
        - name: secret-key
          secret:
            secretName: ssh-key-secret
            optional: true
        - name: config-oci
          configMap:
            name: oci-cli-cm
            optional: true
        initContainers:
          - name: redis-pull-container
            envFrom:
            - configMapRef:
                name: sentinel-backup-env-cm
                optional: true
            - secretRef:
                name: aws-key-secret
                optional: true
            image: fra.ocir.io/discngine1/3decision_kube/redis-backup:0.0.1
            command: ["./entrypoint.sh"]
            args: ["pull"]
            imagePullPolicy: Always
            volumeMounts:
            - mountPath: /root/.ssh/
              name: secret-key
              readOnly: true
            - mountPath: /root/.oci/
              name: config-oci
              readOnly: true
            - mountPath: /data
              name: redis-data
EOT
}

######################
#        HELM
######################

resource "helm_release" "ingress_nginx_release" {
  name             = var.ingress_nginx_chart.name
  chart            = var.ingress_nginx_chart.chart
  namespace        = var.ingress_nginx_chart.namespace
  create_namespace = var.ingress_nginx_chart.create_namespace
  repository       = var.ingress_nginx_chart.repository
  version          = var.ingress_nginx_chart.version
  timeout          = 1200

  values = [<<YAML
    controller:
      service:
        annotations:
          service.beta.kubernetes.io/oci-load-balancer-shape: flexible
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: 10
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: 100
          service.beta.kubernetes.io/oci-load-balancer-security-list-management-mode: "None"
        loadBalancerIP: ${var.lb_public_ip}
    YAML
  ]
}

resource "helm_release" "cert_manager_release" {
  name             = var.cert_manager_chart.name
  chart            = var.cert_manager_chart.chart
  repository       = var.cert_manager_chart.repository
  namespace        = var.cert_manager_chart.namespace
  version          = var.cert_manager_chart.version
  create_namespace = var.cert_manager_chart.create_namespace
  timeout          = 1200

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "helm_release" "sentinel_release" {
  name             = var.redis_sentinel_chart.name
  chart            = var.redis_sentinel_chart.chart
  namespace        = var.redis_sentinel_chart.namespace
  create_namespace = var.redis_sentinel_chart.create_namespace
  version          = var.redis_sentinel_chart.version
  timeout          = 1200
  values           = [local.values_config]
  depends_on       = [kubectl_manifest.sentinel_configmap_redis]
}

resource "helm_release" "external_secrets_chart" {
  name             = var.external_secrets_chart.name
  chart            = var.external_secrets_chart.chart
  repository       = var.external_secrets_chart.repository
  namespace        = var.external_secrets_chart.namespace
  create_namespace = var.external_secrets_chart.create_namespace
  timeout          = 1200
}

resource "helm_release" "reloader_chart" {
  name             = var.reloader_chart.name
  chart            = var.reloader_chart.chart
  repository       = var.reloader_chart.repository
  namespace        = var.reloader_chart.namespace
  create_namespace = var.reloader_chart.create_namespace
  timeout          = 1200
}
