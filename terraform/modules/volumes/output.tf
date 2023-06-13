# volumes Module - Output file for the volumes module

output "public_volume_id" {
  value = aws_ebs_volume.public_data.id
}

output "private_volume_id" {
  value = aws_ebs_volume.private_data.id
}
