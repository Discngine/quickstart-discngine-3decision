# vault Module - Main file for the vault module

locals {
  public_snapshot = {
    "us-east-1"    = "snap-0c90f31c91a6bcd03"
    "eu-central-1" = "snap-0c170db94d14c9c18"
  }
}

resource "aws_ebs_volume" "public_data" {
  availability_zone = var.availability_zone_names[0]
  snapshot_id       = var.public_volume_snapshot != null ? var.public_volume_snapshot : lookup(local.public_snapshot, var.region)
  final_snapshot    = var.public_final_snapshot
  type              = "gp2"
  encrypted         = true
  tags = {
    Name = "3decision-public-data"
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
}
