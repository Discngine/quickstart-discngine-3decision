# volumes Module - Output file for the volumes module
#
# Ionel Panaitescu (ionel.panaitescu@oracle.com)
# Andrei Pirjol (andrei.pirjol@oracle.com)
#       Oracle Cloud Infrastructure
#
# Release (Date): 1.0 (July 2018)
#
# Copyright Oracle, Inc.  All rights reserved.

output "public_volume_id" {
  value = aws_ebs_volume.public_data.id
}

output "private_volume_id" {
  value = aws_ebs_volume.private_data.id
}
