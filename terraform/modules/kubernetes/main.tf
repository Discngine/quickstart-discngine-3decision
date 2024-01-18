# kubernetes Module - Main file for the kubernetes module

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

# If anything is needed to be run once for the 1.8 release add it here
resource "terraform_data" "cleaning_1_8" {
  triggers_replace = [var.tdecision_chart.version]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
if ! helm get notes ${var.tdecision_chart.name} -n ${var.tdecision_chart.namespace}; then
  echo "tdecision not installed, no need for cleaning."
  exit 0
fi
if [[ "${var.tdecision_chart.version}" = "3.0.0"* ]] || [[ "${var.tdecision_chart.version}" = "3.0.1"* ]]; then

  kubectl delete svc -n tdecision --all --force
  kubectl patch ingress tdecision-3decision-helm-ingress -n tdecision -p '{"metadata":{"finalizers":null}}' --type=merge
  sleep 10
  kubectl delete ingress -n tdecision --all --force

  ARN=$(aws elbv2 describe-load-balancers --names lb-3dec --query "LoadBalancers[0].LoadBalancerArn" --output json); ARN="$${ARN//\"/}"
  echo "updating tag on lb $${ARN}"
  aws elbv2 add-tags --resource-arn $${ARN} --tags Key=ingress.k8s.aws/stack,Value=lb-3dec
  echo "1.8 cleaning over"
fi
if [[ "${var.tdecision_chart.version}" = "2.3.7"* ]]; then
  kubectl delete statefulset.apps --all -n ${var.redis_sentinel_chart.namespace} --force
  kubectl delete svc -n tdecision --all --force

  kubectl patch ingress tdecision-3decision-helm-ingress -n tdecision -p '{"metadata":{"finalizers":null}}' --type=merge
  sleep 10
  kubectl delete ingress -n tdecision --all --force

  ARN=$(aws elbv2 describe-load-balancers --names lb-3dec --query "LoadBalancers[0].LoadBalancerArn" --output json); ARN="$${ARN//\"/}"
  echo "updating tag on lb $${ARN}"
  aws elbv2 add-tags --resource-arn $${ARN} --tags Key=ingress.k8s.aws/stack,Value=tdecision/tdecision-3decision-helm-ingress
  echo "Ran 2.3.7 rollback ..."
fi
    EOF
  }
}


locals {
  cm_data = {
    "mapRoles" = <<YAML
- rolearn: ${var.node_group_role_arn}
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes
%{for arn in var.additional_eks_roles_arn}
- rolearn: ${arn}
  username: quickstart-user
  groups:
    - system:masters
%{endfor}
YAML
    "mapUsers" = <<YAML
%{for arn in var.additional_eks_users_arn}
- userarn: ${arn}
  username: quickstart-user
  groups:
    - system:masters
%{endfor}
YAML
  }
}

resource "null_resource" "delete_aws_auth" {
  count = (length(var.additional_eks_roles_arn) > 0 || length(var.additional_eks_users_arn) > 0) ? 1 : 0
  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      
      aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
      export KUBECONFIG=$HOME/.kube/config
      kubectl -n kube-system delete configmap aws-auth --force
      exit 0
    EOT
  }
}

resource "kubernetes_config_map_v1" "aws_auth" {
  count = (length(var.additional_eks_roles_arn) > 0 || length(var.additional_eks_users_arn) > 0) ? 1 : 0

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data       = local.cm_data
  depends_on = [null_resource.delete_aws_auth]
}

resource "kubernetes_storage_class_v1" "encrypted_storage_class" {
  metadata {
    name = "gp2-encrypted"
  }
  parameters = {
    fsType    = "ext4"
    type      = "gp2"
    encrypted = "true"
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  depends_on = [kubernetes_config_map_v1.aws_auth]
}

resource "kubernetes_namespace" "tdecision_namespace" {
  metadata {
    name = var.tdecision_chart.namespace
  }

  depends_on = [kubernetes_config_map_v1.aws_auth]
}

resource "kubernetes_namespace" "redis_namespace" {
  metadata {
    name = "redis-cluster"
  }

  depends_on = [kubernetes_config_map_v1.aws_auth]
}

resource "kubernetes_namespace" "choral_namespace" {
  metadata {
    name = "choral"
  }

  depends_on = [kubernetes_config_map_v1.aws_auth]
}

resource "kubernetes_namespace" "tools_namespace" {
  metadata {
    name = "tools"
  }

  depends_on = [kubernetes_config_map_v1.aws_auth]
}

resource "kubernetes_secret" "jwt_secret" {
  metadata {
    name      = "3decision-jwt-secret"
    namespace = var.tdecision_chart.namespace
  }

  data = {
    "id_rsa"     = var.jwt_ssh_private
    "id_rsa.pub" = var.jwt_ssh_public
  }
  depends_on = [kubernetes_namespace.tdecision_namespace, kubernetes_config_map_v1.aws_auth]
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
              value: ${local.connection_string}
            - name: sq3
              value: /root/sqlcl/bin/sql PD_T1_DNG_THREEDECISION/$${DB_PASSWD}@$${CONNECTION_STRING}
            - name: sqc
              value: /root/sqlcl/bin/sql CHEMBL_29/$${CHEMBL_DB_PASSWD}@$${CONNECTION_STRING}
            - name: sqs
              value: /root/sqlcl/bin/sql SYS/$${SYS_DB_PASSWD}@$${CONNECTION_STRING} as sysdba
          args: [ "sleep infinity" ]
  YAML
  depends_on = [kubernetes_namespace.tools_namespace, kubectl_manifest.ClusterExternalSecret]
}

resource "kubectl_manifest" "secretstore" {
  yaml_body  = <<YAML
---
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secret-store
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${var.region}
      role: ${var.secrets_access_role_arn}
  YAML
  depends_on = [helm_release.external_secrets_chart, kubernetes_config_map_v1.aws_auth]
}

resource "kubectl_manifest" "ClusterExternalSecret" {
  yaml_body = <<YAML
---
apiVersion: external-secrets.io/v1beta1
kind: ClusterExternalSecret
metadata:
  name: database-secrets
spec:
  externalSecretName: database-secrets
  namespaceSelector:
    matchExpressions:
      - {key: kubernetes.io/metadata.name, operator: In, values: [${var.tdecision_chart.namespace}, choral, tools]}
  refreshTime: 1m
  externalSecretSpec:
    refreshInterval: 1m
    secretStoreRef:
      name: aws-secret-store
      kind: ClusterSecretStore
    target:
      name: database-secrets
      creationPolicy: Owner
    data:
    - secretKey: SYS_DB_PASSWD
      remoteRef:
        key: 3dec-admin-db
        property: password
    - secretKey: DB_PASSWD
      remoteRef:
        key: 3dec-pd_t1_dng_threedecision-db
        property: password
    - secretKey: ORACLE_PASSWORD
      remoteRef:
        key: 3dec-pd_t1_dng_threedecision-db
        property: password
    - secretKey: CHEMBL_DB_PASSWD
      remoteRef:
        key: 3dec-chembl_29-db
        property: password
    - secretKey: CHORAL_DB_PASSWD
      remoteRef:
        key: 3dec-choral_owner-db
        property: password
  YAML
  depends_on = [
    kubectl_manifest.secretstore,
    kubernetes_namespace.tdecision_namespace,
    kubernetes_namespace.choral_namespace,
    kubernetes_config_map_v1.aws_auth
  ]
}

resource "kubernetes_secret" "nest_authentication_secrets" {
  metadata {
    name      = "nest-authentication-secrets"
    namespace = var.tdecision_chart.namespace
  }
  data = {
    AZURE_TENANT   = var.azure_oidc.tenant
    AZURE_SECRET   = var.azure_oidc.secret
    GOOGLE_SECRET  = var.google_oidc.secret
    OKTA_DOMAIN    = var.okta_oidc.domain
    OKTA_SERVER_ID = var.okta_oidc.server_id
    OKTA_SECRET    = var.okta_oidc.secret
  }
  depends_on = [kubernetes_namespace.tdecision_namespace, kubernetes_config_map_v1.aws_auth]
}

resource "kubectl_manifest" "sentinel_configmap_redis" {
  for_each = toset([var.tdecision_chart.namespace, "redis-cluster"])

  yaml_body = <<YAML
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sentinel-backup-env-cm
  namespace: ${each.key}
data:
  BUCKET_NAME: ${var.redis_bucket_name}
  PROVIDER: aws
YAML
  depends_on = [
    kubernetes_namespace.redis_namespace,
    kubernetes_namespace.tdecision_namespace,
    kubernetes_config_map_v1.aws_auth
  ]
}

resource "kubernetes_job_v1" "af_bucket_files_push" {

  metadata {
    name      = "job-af-bucket-files-push"
    namespace = var.tdecision_chart.namespace
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name  = "job-af-bucket-files-push"
          image = "fra.ocir.io/discngine1/3decision_kube/alphafold_bucket_push:0.0.2"
          env {
            name  = "PROVIDER"
            value = "AWS"
          }
          env {
            name  = "BUCKET_NAME"
            value = var.alphafold_bucket_name
          }
          env {
            name  = "FTP_LINK"
            value = var.af_ftp_link
          }
          env {
            name  = "FILE_NAME"
            value = var.af_file_name
          }
          env {
            name  = "FILE_NUMBER"
            value = var.af_file_nb
          }
          volume_mount {
            name       = "nfs-pvc-public"
            mount_path = "/publicdata"
          }
        }
        volume {
          name = "nfs-pvc-public"
          persistent_volume_claim {
            claim_name = "${helm_release.tdecision_chart.name}-nfs-pvc-public"
          }
        }
        restart_policy       = "OnFailure"
        service_account_name = "${helm_release.tdecision_chart.name}-s3-access"
      }
    }
    backoff_limit = 3
  }
  wait_for_completion = false
}

resource "kubernetes_job_v1" "af_proteome_download" {
  metadata {
    name      = "af-proteome-download-job"
    namespace = var.tdecision_chart.namespace
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name  = "af-bucket-files-push-job"
          image = "fra.ocir.io/discngine1/3decision_kube/alphafold_proteome_downloader:0.0.1"
          volume_mount {
            name       = "nfs-pvc-public"
            mount_path = "/publicdata"
          }
          image_pull_policy = "Always"
        }
        volume {
          name = "nfs-pvc-public"
          persistent_volume_claim {
            claim_name = "${helm_release.tdecision_chart.name}-nfs-pvc-public"
          }
        }
        restart_policy = "OnFailure"
      }
    }
    backoff_limit = 3
  }
  wait_for_completion = false
}

######################
#        HELM
######################

locals {
  values_config = <<YAML
global:
  storageClass: gp2-encrypted
serviceAccount:
  create: true
  name: sentinel-redis
  annotations:
    eks.amazonaws.com/role-arn: ${var.redis_s3_role_arn}  
commonConfiguration: |-
  # Enable AOF https://redis.io/topics/persistence#append-only-file
  appendonly no
  # Disable RDB persistence, AOF persistence already enabled.
  save 300 1
sentinel:
  enabled: true
  resources:
    requests:
      cpu: 500m
      memory: 500Mi
master:
  service:
    ports:
      redis: 6380
replica:
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
  extraVolumes:
  - name: secret-key
    secret:
      secretName: ssh-key-secret
      optional: true
  initContainers:
    - name: redis-pull-container
      envFrom:
      - configMapRef:
          name: sentinel-backup-env-cm
          optional: true
      image: fra.ocir.io/discngine1/3decision_kube/redis-backup:0.0.1
      command: ["./entrypoint.sh"]
      args: ["pull"]
      imagePullPolicy: Always
      volumeMounts:
      - mountPath: /root/.ssh/
        name: secret-key
        readOnly: true
      - mountPath: /data
        name: redis-data
global:
  redis:
    password: lapin80
auth:
  password: lapin80
delete_statefulsets_id: ${terraform_data.delete_sentinel_statefulsets.id}
YAML
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

  depends_on = [kubernetes_config_map_v1.aws_auth]
}

# Deletes statefulsets on redis upgrade to avoid patching error
# As a security measure, the id of this resource is added to the redis helm values so redis will always be updated if this is launched (so the statefulset is recreated)
resource "terraform_data" "delete_sentinel_statefulsets" {
  triggers_replace = [var.redis_sentinel_chart.version]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
kubectl delete statefulset.apps --all -n ${var.redis_sentinel_chart.namespace} --force
    EOF
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
  depends_on = [
    kubectl_manifest.sentinel_configmap_redis,
    kubernetes_storage_class_v1.encrypted_storage_class,
    kubernetes_config_map_v1.aws_auth,
    terraform_data.delete_sentinel_statefulsets
  ]
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      #!/bin/bash
      
      aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
      export KUBECONFIG=$HOME/.kube/config
      kubectl delete statefulsets -n ${self.namespace} --all --force
      kubectl delete pods -n ${self.namespace} --all --force
    EOT
  }
}

resource "helm_release" "external_secrets_chart" {
  name             = var.external_secrets_chart.name
  chart            = var.external_secrets_chart.chart
  repository       = var.external_secrets_chart.repository
  namespace        = var.external_secrets_chart.namespace
  create_namespace = var.external_secrets_chart.create_namespace
  timeout          = 1200

  depends_on = [kubernetes_config_map_v1.aws_auth]
}

resource "helm_release" "reloader_chart" {
  name             = var.reloader_chart.name
  chart            = var.reloader_chart.chart
  repository       = var.reloader_chart.repository
  namespace        = var.reloader_chart.namespace
  create_namespace = var.reloader_chart.create_namespace
  timeout          = 1200

  depends_on = [kubernetes_config_map_v1.aws_auth]
}


##############
# APP CHARTS
##############

resource "time_static" "tdecision_version_timestamp" {
  triggers = {
    version = var.tdecision_chart.version
  }
}

resource "time_static" "redis_timestamp" {}

locals {
  # Update this list for any version of the 3decision helm chart needing reprocessing
  public_interaction_registration_reprocessing_version_list = ["2.3.3"]
  private_structure_reprocessing_version_list               = ["2.3.4"]
  missing_structure_registration_reprocessing_version_list  = ["2.3.7"]
  alphafold_structure_registration_version_list             = ["3.0.1"]

  reprocessing_timestamp       = timeadd(time_static.tdecision_version_timestamp.rfc3339, "24h")
  redis_reprocessing_timestamp = timeadd(time_static.redis_timestamp.rfc3339, "4h")
  redis_configmap_timestamp    = timeadd(local.redis_reprocessing_timestamp, "24h")

  launch_public_interaction_registration_reprocessing = contains(local.public_interaction_registration_reprocessing_version_list, var.tdecision_chart.version)
  launch_private_structure_reprocessing               = contains(local.private_structure_reprocessing_version_list, var.tdecision_chart.version)
  launch_missing_structure_registration_reprocessing  = contains(local.missing_structure_registration_reprocessing_version_list, var.tdecision_chart.version)
  launch_alphafold_structure_registration             = contains(local.alphafold_structure_registration_version_list, var.tdecision_chart.version)
}

locals {
  connection_string = "${var.db_endpoint}/${var.db_name}"
  values            = <<YAML
oracle:
  connectionString: ${local.connection_string}
  hostString: ${var.db_endpoint}/
  pdbString: ${var.db_name}
volumes:
  storageClassName: gp2-encrypted
  claimPods:
    backend:
      publicdata:
        awsElasticBlockStore:
          fsType: ext4
          volumeID: ${var.public_volume_id}
          availabilityZone: ${var.availability_zone_names[0]}
      privatedata:
        awsElasticBlockStore:
          fsType: ext4
          volumeID: ${var.private_volume_id}
          availabilityZone: ${var.availability_zone_names[0]}
ingress:
  host: ${var.domain}
  certificateArn: ${var.certificate_arn}
  visibility: ${var.load_balancer_type}
  ui:
    host: ${var.main_subdomain}
    additionalHosts: [${join(", ", var.additional_main_fqdns)}]
  api:
    host: ${var.api_subdomain}
  react:
    host: ${var.registration_subdomain}
  class: alb
nest:
  ReprocessingEnv:
    public_interaction_registration_reprocessing_timestamp:
      value: ${local.launch_public_interaction_registration_reprocessing ? local.reprocessing_timestamp : "2000-01-01T00:00:00"}
    rcsb_str_reg_repro_timestamp:
      value: ${local.launch_missing_structure_registration_reprocessing ? local.reprocessing_timestamp : "2000-01-01T00:00:00"}
    redis_synchro_timestamp:
      value: ${local.redis_reprocessing_timestamp}
    private_structures_reprocessing_event_types:
      value: rcsbStructureRegistration,sequenceMappingAnalysis,pocketDetectionAnalysis,ligandCavityOverlapAnalysis,pocketFeaturesAnalysis,interactionRegistration
    private_structure_reprocessing_timestamp:
      value: ${local.launch_private_structure_reprocessing ? local.reprocessing_timestamp : "2000-01-01T00:00:00"}
    alphafold_structure_registration_timestamp:
      value: ${local.launch_alphafold_structure_registration ? local.reprocessing_timestamp : "2000-01-01T00:00:00"}
  env:
    okta_client_id:
      name: OKTA_CLIENT_ID
      value: ${var.okta_oidc.client_id}
    okta_redirect_uri:
      name: OKTA_REDIRECT_URI
      value: https://${var.api_subdomain}.${var.domain}/auth/okta/callback
    azure_client_id:
      name: AZURE_CLIENT_ID
      value: ${var.azure_oidc.client_id}
    azure_redirect_uri:
      name: AZURE_REDIRECT_URI
      value: https://${var.api_subdomain}.${var.domain}/auth/azure/callback
    google_client_id:
      name: GOOGLE_CLIENT_ID
      value: ${var.google_oidc.client_id}
    google_redirect_uri:
      name: GOOGLE_REDIRECT_URI
      value: https://${var.api_subdomain}.${var.domain}/auth/google/callback
    bucket_name:
      name: "ALPHAFOLD_BUCKET_NAME"
      value: ${var.alphafold_bucket_name}
    aws_object_storage_region:
      name: AWS_OBJECT_STORAGE_REGION
      value: ${var.region}

nfs:
  public:
    serviceIP: ${cidrhost(var.eks_service_cidr, 265)}
  private:
    serviceIP: ${cidrhost(var.eks_service_cidr, 266)}
rbac:
  namespaced:
    s3Access:
      annotations:
        eks.amazonaws.com/role-arn: ${var.alphafold_s3_role_arn}
  cluster:
    redisBackup:
      annotations:
        eks.amazonaws.com/role-arn: ${var.redis_s3_role_arn}
redis:
  nodeSelector: null
pocket_features:
  nodeSelector: null
scientific_monolith:
  nodeSelector: null
YAML

  # This makes sure the helm chart is updated if we change the deletion script
  final_values = <<YAML
${local.values}
aws_destroy_resources: ${null_resource.delete_resources.id}
YAML
}

# This resets the passwords of schemas CHEMBL_29 and PD_T1_DNG_THREEDECISION
# It is aimed to be used on new environments that have unknown passwords set in the backup
resource "terraform_data" "reset_passwords" {
  count = 0
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
if helm get notes ${var.tdecision_chart.name} -n ${var.tdecision_chart.namespace} &> /dev/null; then
  echo "tdecision already running, password reset aborted."
  exit 0
fi
cat > reset_passwords.yaml << YAML
---
apiVersion: v1
kind: Pod
metadata:
  name: reset-passwords
  namespace: ${var.tdecision_chart.namespace}
spec:
  restartPolicy: Never
  containers:
    - name: reset-passwords
      image: fra.ocir.io/discngine1/3decision_kube/sqlcl:latest
      command: [ "/bin/bash", "-c", "--" ]
      envFrom:
      - secretRef:
          name: database-secrets
      env:
        - name: CONNECTION_STRING
          value: ${local.connection_string}
      args:
        - echo 'resetting passwords';
          echo -ne 'ALTER USER CHEMBL_29 IDENTIFIED BY "\$${CHEMBL_DB_PASSWD}" ACCOUNT UNLOCK;
          ALTER USER PD_T1_DNG_THREEDECISION IDENTIFIED BY "\$${DB_PASSWD}" ACCOUNT UNLOCK;' > reset_passwords.sql;
          exit | /root/sqlcl/bin/sql ADMIN/\$${SYS_DB_PASSWD}@\$${CONNECTION_STRING} @reset_passwords.sql;
YAML
kubectl apply -f reset_passwords.yaml
rm reset_passwords.yaml
    EOF
  }
  lifecycle {
    ignore_changes = all
  }
  depends_on = [kubectl_manifest.ClusterExternalSecret]
}

# This deletes both the CHORAL_OWNER user and choral indexes
# It is aimed to be used on new environments that would retrieve this data from a backup when it has to be installed
resource "terraform_data" "clean_choral" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
if kubectl get deploy -n choral | grep choral &> /dev/null; then
  echo "choral already running, cleaning aborted."
  exit 0
fi
cat > clean_choral.yaml << YAML
---
apiVersion: v1
kind: Pod
metadata:
  name: clean-choral
  namespace: choral
spec:
  restartPolicy: Never
  containers:
    - name: clean-choral
      image: fra.ocir.io/discngine1/3decision_kube/sqlcl:latest
      command: [ "/bin/bash", "-c", "--" ]
      envFrom:
      - secretRef:
          name: database-secrets
      env:
        - name: CONNECTION_STRING
          value: ${local.connection_string}
      args:
        - echo 'dropping chembl indexes';
          echo -ne 'DROP INDEX IDX_CHOR_STR_CMP_STRUC FORCE;
          DROP INDEX IDX_CHOR_TAU_CMP_STRUC FORCE;
          DROP INDEX IDX_CHOR_TAUISO_CMP_STRUC FORCE;
          DROP INDEX IDX_CHOR_STRICT_CMP_STRUC FORCE;' > drop_chembl_index.sql;
          exit | /root/sqlcl/bin/sql CHEMBL_29/\$${CHEMBL_DB_PASSWD}@\$${CONNECTION_STRING} @drop_chembl_index.sql;
          echo 'dropping tdec indexes';
          echo -ne 'DROP INDEX IDX_CHOR_STR_SMALL_MOL_SMILES FORCE;
          DROP INDEX IDX_CHOR_TAU_SMALL_MOL_SMILES FORCE;
          DROP INDEX IDX_CHOR_TAUISO_SMS FORCE;
          DROP INDEX IDX_CHOR_STRISO_SMS FORCE;' > drop_t1_index.sql;
          exit | /root/sqlcl/bin/sql PD_T1_DNG_THREEDECISION/\$${DB_PASSWD}@\$${CONNECTION_STRING} @drop_t1_index.sql;
          echo 'dropping choral owner schema';
          echo -ne 'DROP USER CHORAL_OWNER CASCADE;' > drop_choral_owner.sql;
          exit | /root/sqlcl/bin/sql ADMIN/\$${SYS_DB_PASSWD}@\$${CONNECTION_STRING} @drop_choral_owner.sql
YAML
kubectl delete -n choral pod/clean-choral
kubectl apply -f clean_choral.yaml
rm clean_choral.yaml
    EOF
  }
  lifecycle {
    ignore_changes = all
  }
  depends_on = [kubectl_manifest.ClusterExternalSecret]
}

# This keeps the CONFORMATION_DEPENDENT_ANALYSIS_EVENT_TTL value low in a seperate 3decision configmap until a day after redis reprocessing
# If this is not done the reprocessing will cache for too long and break the app
# The patch is only done once since patching the configmap restarts most pods, so it has to be rerun if the chart is updated since that will reset the value
resource "terraform_data" "redis_synchro_configmap_change" {
  triggers_replace = [local.redis_configmap_timestamp, helm_release.tdecision_chart.metadata.0.revision]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
target_time=$(date -d "${local.redis_configmap_timestamp}" +"%s")
current_time=$(date +"%s")
time_diff=$(($${target_time} - $${current_time}))
if [ $${time_diff} -lt 0 ]; then
  echo "redis synchro already passed... not launching pod."
  exit 0
fi

aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
cat > redis_synchro.yaml << YAML
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: synchro-redis
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: synchro-redis
rules:
  - apiGroups:
    - ""
    resourceNames:
    - nest-env-configmap
    resources:
    - configmaps
    verbs:
    - patch
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: synchro-redis
subjects:
- kind: ServiceAccount
  name: synchro-redis
roleRef:
  kind: Role
  name: synchro-redis
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Pod
metadata:
  name: synchro-redis
spec:
  serviceAccountName: synchro-redis
  restartPolicy: Never
  containers:
    - name: synchro-redis
      image: alpine/curl:8.4.0
      command: ["/bin/sh", "-c"]
      args:
        - |
          target_time=\$(date -d \$(echo "${local.redis_configmap_timestamp}" | tr -d "TZ") +"%s")
          current_time=\$(date +"%s")
          time_diff=\$((\$${target_time} - \$${current_time}))
          if [ \$${time_diff} -gt 0 ]; then
              sec=/var/run/secrets/kubernetes.io/serviceaccount
              curl -sS \
                -H "Authorization: Bearer \$(cat \$${sec}/token)" \
                -H "Content-Type: application/strategic-merge-patch+json" \
                --cacert \$${sec}/ca.crt \
                --request PATCH \
                --data '{"data":{"CONFORMATION_DEPENDENT_ANALYSIS_EVENT_TTL":"600"}}' \
                https://"\$${KUBERNETES_SERVICE_HOST}"/api/v1/namespaces/${var.tdecision_chart.namespace}/configmaps/nest-env-configmap

              echo "Sleeping for \$${time_diff} seconds until ${local.redis_configmap_timestamp}"

              sleep \$${time_diff}

              sec=/var/run/secrets/kubernetes.io/serviceaccount
              curl -sS \
                -H "Authorization: Bearer \$(cat \$${sec}/token)" \
                -H "Content-Type: application/strategic-merge-patch+json" \
                --cacert \$${sec}/ca.crt \
                --request PATCH \
                --data '{"data":{"CONFORMATION_DEPENDENT_ANALYSIS_EVENT_TTL":"7890000"}}' \
                https://"\$${KUBERNETES_SERVICE_HOST}"/api/v1/namespaces/${var.tdecision_chart.namespace}/configmaps/nest-env-configmap
              echo "Woke up at \$(date)"
          else
              echo "The target time has already passed."
          fi
YAML
kubectl delete -f redis_synchro.yaml -n ${var.tdecision_chart.namespace}
kubectl apply -f redis_synchro.yaml -n ${var.tdecision_chart.namespace}
rm -f redis_synchro.yaml
    EOF
  }
  lifecycle {
    ignore_changes = all
  }
  depends_on = [helm_release.tdecision_chart]
}

resource "helm_release" "tdecision_chart" {
  name       = var.tdecision_chart.name
  repository = var.tdecision_chart.repository
  chart      = var.tdecision_chart.version == "2.3.7" ? "3decision-helm" : var.tdecision_chart.chart
  version    = var.tdecision_chart.version
  namespace  = var.tdecision_chart.namespace
  wait       = false

  values = [local.final_values]
  depends_on = [
    kubernetes_storage_class_v1.encrypted_storage_class,
    helm_release.cert_manager_release,
    kubectl_manifest.ClusterExternalSecret,
    kubernetes_secret.nest_authentication_secrets,
    helm_release.aws_load_balancer_controller,
    kubernetes_config_map_v1.aws_auth,
    null_resource.delete_resources,
    terraform_data.reset_passwords,
    terraform_data.cleaning_1_8
  ]

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      #!/bin/bash
      
      aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
      export KUBECONFIG=$HOME/.kube/config
      kubectl delete -n ${self.namespace} cronjob --all --force
      kubectl delete -n ${self.namespace} job --all --force
      kubectl delete deployments -n ${self.namespace} --all --force
      kubectl delete pods -n ${self.namespace} --all --force
      kubectl delete ingress -n ${self.namespace} --all --force
      kubectl get all -n ${self.namespace}
      echo "finished deleting resources"
    EOT
  }
}

resource "null_resource" "delete_resources" {
  triggers = {
    name       = var.tdecision_chart.name
    repository = var.tdecision_chart.repository
    chart      = var.tdecision_chart.chart
    version    = var.tdecision_chart.version
    namespace  = var.tdecision_chart.namespace
    values     = local.values
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      
      aws eks update-kubeconfig --name EKS-tdecision --kubeconfig $HOME/.kube/config
      export KUBECONFIG=$HOME/.kube/config
      kubectl delete deployments -n ${var.tdecision_chart.namespace} --all --force
    EOT
  }
}

resource "helm_release" "choral_chart" {
  name       = var.choral_chart.name
  repository = var.choral_chart.repository
  chart      = var.choral_chart.chart
  version    = var.choral_chart.version
  namespace  = var.choral_chart.namespace
  values = [<<YAML
    oracle:
      connectionString: ${local.connection_string}
    pvc:
      storageClassName: gp2-encrypted
  YAML
  ]
  timeout = 1200
  depends_on = [
    kubernetes_storage_class_v1.encrypted_storage_class,
    kubectl_manifest.ClusterExternalSecret,
    helm_release.aws_load_balancer_controller,
    kubernetes_config_map_v1.aws_auth,
    terraform_data.clean_choral,
    terraform_data.cleaning_1_8
  ]
}

resource "helm_release" "chemaxon_ms_chart" {
  name             = var.chemaxon_ms_chart.name
  chart            = var.chemaxon_ms_chart.chart
  namespace        = var.chemaxon_ms_chart.namespace
  create_namespace = var.chemaxon_ms_chart.create_namespace
  version          = var.chemaxon_ms_chart.version
  timeout          = 1200
}

locals {
  oidc_issuer = element(split("https://", var.eks_oidc_issuer), 1)
}

resource "aws_iam_role" "load_balancer_controller" {
  name_prefix = "3decision-load-balancer-controller"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${var.account_id}:oidc-provider/${local.oidc_issuer}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${local.oidc_issuer}:aud": [
            "sts.amazonaws.com",
            "sts.${var.region}.amazonaws.com"
          ],
          "${local.oidc_issuer}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
EOF

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicReadOnly"
  ]

  inline_policy {
    name   = "load-balancer-controller-policy"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeAddresses",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeVpcs",
        "ec2:DescribeVpcPeeringConnections",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeInstances",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeTags",
        "ec2:GetCoipPoolUsage",
        "ec2:DescribeCoipPools",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeListenerCertificates",
        "elasticloadbalancing:DescribeSSLPolicies",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:DescribeUserPoolClient",
        "acm:ListCertificates",
        "acm:DescribeCertificate",
        "iam:ListServerCertificates",
        "iam:GetServerCertificate",
        "waf-regional:GetWebACL",
        "waf-regional:GetWebACLForResource",
        "waf-regional:AssociateWebACL",
        "waf-regional:DisassociateWebACL",
        "wafv2:GetWebACL",
        "wafv2:GetWebACLForResource",
        "wafv2:AssociateWebACL",
        "wafv2:DisassociateWebACL",
        "shield:GetSubscriptionState",
        "shield:DescribeProtection",
        "shield:CreateProtection",
        "shield:DeleteProtection"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "arn:aws:ec2:*:*:security-group/*",
      "Condition": {
        "StringEquals": {
          "ec2:CreateAction": "CreateSecurityGroup"
        },
        "Null": {
          "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "arn:aws:ec2:*:*:security-group/*",
      "Condition": {
        "Null": {
          "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
          "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DeleteSecurityGroup"
      ],
      "Resource": "*",
      "Condition": {
        "Null": {
          "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateTargetGroup"
      ],
      "Resource": "*",
      "Condition": {
        "Null": {
          "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:CreateRule",
        "elasticloadbalancing:DeleteRule"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags"
      ],
      "Resource": [
        "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
        "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
        "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
      ],
      "Condition": {
        "Null": {
          "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
          "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags"
      ],
      "Resource": [
        "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
        "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
        "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
        "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:SetIpAddressType",
        "elasticloadbalancing:SetSecurityGroups",
        "elasticloadbalancing:SetSubnets",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:DeleteTargetGroup"
      ],
      "Resource": "*",
      "Condition": {
        "Null": {
          "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:AddTags"
      ],
      "Resource": [
        "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
        "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
        "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
      ],
      "Condition": {
        "StringEquals": {
          "elasticloadbalancing:CreateAction": [
            "CreateTargetGroup",
            "CreateLoadBalancer"
          ]
        },
        "Null": {
          "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets"
      ],
      "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:SetWebAcl",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:AddListenerCertificates",
        "elasticloadbalancing:RemoveListenerCertificates",
        "elasticloadbalancing:ModifyRule"
      ],
      "Resource": "*"
    }
  ]
}
EOF
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  values = [<<YAML
    clusterName: ${var.cluster_name}
    hostNetwork: false
    image:
      repository: public.ecr.aws/eks/aws-load-balancer-controller
    nodeSelector:
      kubernetes.io/os: linux
    region: ${var.region}
    replicaCount: 1
    resources:
      limits:
        cpu: 100m
        memory: 80Mi
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.load_balancer_controller.arn}
      create: true
      name: aws-load-balancer-controller
    vpcId: ${var.vpc_id}
  YAML
  ]
  depends_on = [helm_release.cert_manager_release, kubernetes_config_map_v1.aws_auth]
}
