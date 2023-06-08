# database Module - Variables file for the database module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

variable "region" {}
variable "account_id" {}
variable "force_destroy" {}
variable "snapshot_identifier" {}
variable "high_availability" {}
variable "instance_type" {}
variable "node_security_group_id" {}
variable "vpc_id" {}
variable "private_subnet_ids" {}
variable "backup_retention_period" {}
variable "license_type" {}