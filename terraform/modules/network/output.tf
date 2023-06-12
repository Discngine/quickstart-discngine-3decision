# network Module - Ouput file for the network module

output "vpc_id" {
  value = aws_vpc.my_vpc.id
}

output "private_subnet_ids" {
  value = aws_subnet.private_subnet[*].id
}
