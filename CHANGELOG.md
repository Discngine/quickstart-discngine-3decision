# Changelog
All notable changes to this project will be documented in this file.
Dates are ISO8601 / YYYY-MM-DD
Version equals the version of the equivalent 3decision helm chart release
Add a `-0` with incrementing numbers in case of a terraform / cloudformation change without equivalent helm changes 

## [3.5.12] - 2025-03-31

### Cloudformation
#### Added
- NA

#### Changed
- NA

#### Removed
- Cloudformation linting job from CI configuration @JonathanManass

### Terraform
#### Added
- Oracle Data Pump data migration module with S3 integration for importing database backups @aphilippejolivel
- Data migration validation gate to ensure migration completes before Helm chart deployment @aphilippejolivel
- IAM role and policy for RDS S3 integration (Oracle Data Pump) @aphilippejolivel
- RDS allocated storage variable for configurable database storage @aphilippejolivel
- RDS storage increase script with CloudWatch metrics and usability checks @aphilippejolivel
- Gateway API support (HTTPRoute) for AWS Load Balancer Controller with ALBGatewayAPI feature gate @aphilippejolivel
- CRD updates for AWS Load Balancer Controller and Gateway API @aphilippejolivel
- Load balancer access logging and deletion protection on ingress @aphilippejolivel
- Destroy-time kubeconfig setup via `null_resource` to replace hardcoded EKS cluster names in destroy provisioners @aphilippejolivel

#### Changed
- Updated default 3decision chart version to 3.5.12 @aphilippejolivel
- Updated AWS Load Balancer Controller Helm chart to v3.0.0 with expanded IAM permissions @aphilippejolivel
- Increased Helm release timeout from 7200 to 72000 seconds @JonathanManass
- Enhanced destroy provisioners for `tdecision_chart` with Gateway API resource cleanup and finalizer removal @aphilippejolivel
- Refactored destroy provisioners to use dynamic cluster name instead of hardcoded `EKS-tdecision` @JonathanManass
- Updated postgres chart init script @JonathanManass

#### Removed
- NA

## [3.5.1] - 2025-11-06

### Cloudformation
#### Added
- MonitoringEmail parameter for ALB health notifications in both main and existing VPC templates @JonathanManass

#### Changed
- Updated default tdecision chart version to 3.5.1 @JonathanManass
- Updated Kubernetes default Version to 1.34 @JonathanManass
#### Removed
- NA

### Terraform
#### Added
- Added ALB health monitoring @JonathanManass
- Lambda-based recurring notification system for persistent alarm states @JonathanManass
- SNS topic and subscription management for monitoring alerts @JonathanManass
- Database maintenance window configuration variable @JonathanManass
- IAM policies for Lambda and EventBridge with appropriate permissions @JonathanManass

#### Changed
- Updated EKS cluster version to 1.34 with Amazon Linux 2023 AMI compatibility @JonathanManass
- Migrated from AL2 bootstrap.sh to AL2023 nodeadm configuration system @JonathanManass
- Implemented cloudinit_config for EKS node configuration with maxPods=110 @JonathanManass
- Updated SSM parameter references for EKS AMI release versions @JonathanManass
- Refactored user data handling for better custom AMI support @JonathanManass
- Set default for username_is_email variable to true @JonathanManass
- Updated EBS snapshot ID @JonathanManass

#### Removed
- Legacy AL2 user data configuration methods @JonathanManass

## [3.4.5] - 2025-07-10
### Cloudformation
#### Added
- NA

#### Changed
- NA

#### Removed
- NA

### Terraform
#### Added
- NA

#### Changed
- Updated default 3decision version to 3.4.5. @JonathanManass

#### Removed
- NA

## [3.4.4] - 2025-06-18
### Cloudformation
#### Added
- Added VolumeAvailabilityZone parameter to control where block volumes are created. @JonathanManass
- Added Templates upload to specific directory on release. @JonathanManass

#### Changed
- NA

#### Removed
- NA

### Terraform
#### Added
- Added pod identity association for license download. @JonathanManass

#### Changed
- Updated default 3decision version to 3.4.4. @JonathanManass

#### Removed
- NA

## [3.4.3] - 2025-06-18
### Cloudformation
#### Added
- Enforced IMDSv2 (Instance Metadata Service v2) for BootNode EC2 instance using MetadataOptions. @JonathanManass
- Added S3 bucket policy to StateBucket to enforce SSL-only access. @JonathanManass

#### Changed
- NA

#### Removed
- NA

### Terraform
#### Added
- S3 bucket policy resource to enforce SSL-only access in storage module. @JonathanManass
- README for Lambda function packaging instructions. @JonathanManass
- Exposed admin_username and db_instance_identifier outputs in database module and passed to secrets module. @JonathanManass
- Added app bucket to store loadbalancer access logs. @JonathanManass
- Enabled logging of recommended types for the EKS cluster. @JonathanManass

#### Changed
- Enabled KMS key rotation by default in main and eks modules. @JonathanManass
- Set k8s_public_access default to false. @JonathanManass
- Updated outputs and variables for secrets and kubernetes modules to support new features. @JonathanManass
- Updated allowed_service_accounts logic in storage module. @JonathanManass
- Set terraform providers to fixed versions. @JonathanManass
- Updated some helm charts / images registries to our own. @JonathanManass 

#### Removed
- NA

## [3.4.2] - 2025-06-17
### Cloudformation
#### Added
- Support for EKS Kubernetes versions 1.30–1.32 (default is now 1.32). @JonathanManass

#### Changed
- NA

#### Removed
- NA

### Terraform
#### Added
- Added postgres helm_release with bingo cartridge. @JonathanManass
- Optional KMS key creation and related variables for encryption in main and database modules. @JonathanManass
- Optional snapshot copy logic and variables in the database module. @JonathanManass
- Made resource creation for EKS, node groups, and OIDC provider conditional to create in an existing cluster. @JonathanManass
- Helm release and PVC deletion logic for cert-manager and Redis upgrades. @JonathanManass
- Additional variables for flexibility in EKS and database modules. @JonathanManass
- Added possibility to control external secrets via the pod identity association addon. @JonathanManass
- Added possibility to disable secret rotation. @JonathanManass

#### Changed
- Lowered externalSecrets update interval to minimize the chance of user locks. @JonathanManass
- Updated Oracle rotation lambda to unlock user after a minute if not accessible to avoid the application locking it during the update. @JonathanManass
- Refactored EKS, database, and secrets modules to use conditional resource creation and locals for cluster references. @JonathanManass
- Updated outputs to use local cluster references and conditional logic. @JonathanManass
- Updated storage class handling and made it conditional on encryption. @JonathanManass
- Updated secret and OIDC handling for PingID authentication. @JonathanManass
- Update redis chart version. @JonathanManass

#### Removed
- Removed choral & chemaxon release and related resources (database secrets, kubernetes resources) @JonathanManass

---
## [3.1.5] - 2025-01-10
### Cloudformation
#### Added
- NA

#### Changed
- NA

#### Removed
- NA

### Terraform
#### Added
- Added priority classes used by helm charts to prioritize pods @JonathanManass
- Updated helm chart default versions @JonathanManass

#### Changed
- Updated registry for all images to new prod registry @JonathanManass

#### Removed
- Nothing
---
## [3.1.4] - 2024-10-15
### Cloudformation
#### Added
- Added a codebuild project to run the terraform code @JonathanManass
- Added a parameter to make the creation of a seperate ec2 instance optional @JonathanManass
- Added a parameter to add tags to all terraform created resources @JonathanManass

#### Changed
- Updated EKS default version to 1.29 @JonathanManass
- Updated default role to run on codebuild and to allow tagging all resources @JonathanManass

#### Removed
- Removed the SSM Association to run terraform on an ec2 instance @JonathanManass

### Terraform
#### Added
- Added default tags to add tags to all resources @JonathanManass

#### Changed
- Updated 3decision helm chart default value to 3.1.4 @JonathanManass
- Updated sqlcl images tags @JonathanManass
- Updated hoststring to match new helm chart nomenclature @JonathanManass

#### Removed
- Nothing
---
## [3.0.7] - 2024-07-12
### Cloudformation
#### Added
- Added a permission to the user to update the description of IAM roles @JonathanManass

#### Changed
- Nothing

#### Removed
- Nothing

### Terraform
#### Added
- Added the reloader annotation to the sqlcl container @JonathanManass
- Added a reprocessing timestamp for the transfer from redis to oracle @aphilippejolivel

#### Changed
- Updated 3decision helm chart default value to 3.0.7 @aphilippejolivel
- Updated the time at which secrets update from every 30 days to every first sunday of the month at 2 AM @JonathanManass

#### Removed
- Removed the Redis bucket and its references @JonathanManass
---

## [3.0.5] - 2024-05-02
### Cloudformation
#### Added
- Added InboundCidrs parameter to specify ingress cidr blocks for the loadbalancer security group @JonathanManass

#### Changed
- Nothing

#### Removed
- Nothing

### Terraform
#### Added
- Added inbound_cidrs parameter passed to the helm chart @JonathanManass

#### Changed
- Updated 3decision helm chart default value to 3.0.5 @JonathanManass

#### Removed
- Nothing
---
