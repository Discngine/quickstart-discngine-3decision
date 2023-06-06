# vault Module - Main file for the vault module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

resource "aws_ebs_volume" "public_data" {
  availability_zone = "eu-central-1a"
  snapshot_id = "snap-0c170db94d14c9c18"
  encrypted = true
}
