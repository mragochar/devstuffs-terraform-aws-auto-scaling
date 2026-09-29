output "vpc_details" {
  value = {
    name = aws_vpc.auto_scaling.tags["Name"]
    cidr = aws_vpc.auto_scaling.cidr_block
    id   = aws_vpc.auto_scaling.id
    igw  = aws_internet_gateway.igw.id != "" ? aws_internet_gateway.igw.id : "not associated"
  }
}

output "subnets" {
  description = "Map of subnet names to their AWS Subnet IDs in both AZs"

  value = merge(
    {
      for key, subnet in aws_subnet.subnets_az_1a : key => subnet.cidr_block
    },
    {
      for key, subnet in aws_subnet.subnets_az_1b : key => subnet.cidr_block
    }
  )
}

output "route_tables" {
  value = { for key, route_table_details in aws_route_table.all : key => route_table_details.id }
}

output "load_balancer_address" {
  value = aws_lb.auto_scaling.dns_name
}
