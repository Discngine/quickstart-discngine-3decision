# vault Module - Main file for the vault module

locals {
  public_snapshot = {
    "us-east-1"    = "snap-058548b06fb983109"
    "eu-central-1" = "snap-0db1c91fab77813de"
  }
}

resource "aws_ebs_volume" "public_data" {
  availability_zone = var.availability_zone_names[0]
  snapshot_id       = var.public_volume_snapshot != "" ? var.public_volume_snapshot : lookup(local.public_snapshot, var.region)
  final_snapshot    = false
  type              = "gp2"
  encrypted         = true
  tags = {
    Name = "3decision-public-data"
  }
  lifecycle {
    ignore_changes = [availability_zone, snapshot_id, encrypted, kms_key_id, final_snapshot]
  }
  timeouts {
    delete = "180m"
  }
}

resource "aws_ebs_volume" "private_data" {
  availability_zone = var.availability_zone_names[0]
  snapshot_id       = var.private_volume_snapshot
  type              = "gp2"
  final_snapshot    = var.private_final_snapshot
  size              = 200
  encrypted         = true
  tags = {
    Name = "3decision-private-data"
  }
  lifecycle {
    ignore_changes = [availability_zone, snapshot_id, encrypted, kms_key_id, final_snapshot]
  }
  timeouts {
    delete = "120m"
  }
}
