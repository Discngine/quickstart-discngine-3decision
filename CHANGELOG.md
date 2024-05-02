# Changelog
All notable changes to this project will be documented in this file.
Dates are ISO8601 / YYYY-MM-DD
Version equals the version of the equivalent 3decision helm chart release
Add a `-0` with incrementing numbers in case of a terraform / cloudformation change without equivalent helm changes 

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
