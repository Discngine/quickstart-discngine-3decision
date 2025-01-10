# Changelog
All notable changes to this project will be documented in this file.
Dates are ISO8601 / YYYY-MM-DD
Version equals the version of the equivalent 3decision helm chart release
Add a `-0` with incrementing numbers in case of a terraform / cloudformation change without equivalent helm changes 

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
