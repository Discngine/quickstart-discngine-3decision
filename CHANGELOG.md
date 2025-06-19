# Changelog
All notable changes to this project will be documented in this file.
Dates are ISO8601 / YYYY-MM-DD
Version equals the version of the equivalent 3decision helm chart release
Add a `-0` with incrementing numbers in case of a terraform / cloudformation change without equivalent helm changes 

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
- Set terraform providers to fixed versions

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
