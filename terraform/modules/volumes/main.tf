# vault Module - Main file for the vault module

locals {
  public_snapshot = {
    "us-east-1"    = "snap-058548b06fb983109"
    "eu-central-1" = "snap-004dcbe60320ccba6"
  }
}

resource "aws_ebs_volume" "public_data" {
  availability_zone = var.availability_zone_names[var.public_volume_availability_zone]
  snapshot_id       = var.public_volume_snapshot != "" ? var.public_volume_snapshot : lookup(local.public_snapshot, var.region)
  final_snapshot    = false
  type              = var.storage_type
  encrypted         = var.encrypt_volumes
  kms_key_id        = var.kms_key_id
  tags = merge({
    Name = "3decision-public-data"
  }, var.volumes_additional_tags)
  lifecycle {
    ignore_changes = [availability_zone, snapshot_id, encrypted, kms_key_id, final_snapshot, tags, tags_all]
  }
  timeouts {
    delete = "180m"
  }
}

resource "aws_ebs_volume" "private_data" {
  availability_zone = var.availability_zone_names[var.private_volume_availability_zone]
  snapshot_id       = var.private_volume_snapshot
  type              = var.storage_type
  final_snapshot    = var.private_final_snapshot
  size              = 200
  encrypted         = var.encrypt_volumes
  kms_key_id        = var.kms_key_id
  tags = merge({
    Name = "3decision-private-data"
  }, var.volumes_additional_tags)
  lifecycle {
    ignore_changes = [availability_zone, snapshot_id, encrypted, kms_key_id, final_snapshot, tags, tags_all]
  }
  timeouts {
    delete = "120m"
  }
}
