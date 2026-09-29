# -----------------------
# VPC
# -----------------------
variable "vpc_name" {
  type    = string
  default = "auto-scaling"
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/24"
}

# -----------------------
# Subnets
# -----------------------
variable "availability_zones" {
  type = map(string)
  default = {
    "az_1a" = "ap-south-1a",
    "az_1b" = "ap-south-1b"
  }
}

variable "subnets_az_1a" {
  description = "subnets in ap-south-1a"
  type        = map(string)
  default = {
    "private-subnet-1a" = "10.0.0.0/26"
    "public-subnet-1a"  = "10.0.0.64/26"
  }
}

variable "subnets_az_1b" {
  description = "subnets in ap-south-1b"
  type        = map(string)
  default = {
    "private-subnet-1b" = "10.0.0.128/26"
    "public-subnet-1b"  = "10.0.0.192/26"
  }
}

# -----------------------
# Route Tables
# -----------------------
locals {
  subnet_names = concat(
    keys(var.subnets_az_1a),
    keys(var.subnets_az_1b)
  )

  route_table_names = [
    for subnet_name in local.subnet_names : "rt-${subnet_name}"
  ]
}

# public subnet to route table mapping
locals {
  public_subnets_route_tables = {
    for subnet_name, subnet in merge(
      aws_subnet.subnets_az_1a,
      aws_subnet.subnets_az_1b
    ) :
    subnet_name => aws_route_table.all["rt-${subnet_name}"].id
    if startswith(subnet_name, "public-")
  }
}

# private subnet to route table mapping
locals {
  private_subnets_route_tables = {
    for subnet_name, subnet in merge(
      aws_subnet.subnets_az_1a,
      aws_subnet.subnets_az_1b
    ) :
    subnet_name => aws_route_table.all["rt-${subnet_name}"].id
    if startswith(subnet_name, "private-")
  }
}

# private route table id to nat gateway id mapping 
locals {
  private_route_table_ids = [
    for key, rtb in aws_route_table.all :
    rtb.id if startswith(key, "rt-private-")
  ]

  ngw_ids = [
    for ngw in aws_nat_gateway.ngw : ngw.id
  ]

  private_route_table_ids_to_ngw_id = zipmap(
    local.private_route_table_ids,
    local.ngw_ids
  )
}

# -----------------------
# Launch Template
# -----------------------
variable "launch_template_name" {
  type    = string
  default = "lt-auto-scaling"
}

variable "security_group_id" {
  type = string
  default = "sg-0f67f474be904cb21"
}

# -----------------------
# Load Balancers and ASG
# -----------------------
locals {
  public_subnets = {
    for subnet_name, subnet in merge(
      aws_subnet.subnets_az_1a,
      aws_subnet.subnets_az_1b
    ) :
    subnet_name => subnet.id
    if startswith(subnet.tags["Name"], "public-")
  }

  private_subnets = {
    for subnet_name, subnet in merge(
      aws_subnet.subnets_az_1a,
      aws_subnet.subnets_az_1b
    ) :
    subnet_name => subnet.id
    if startswith(subnet.tags["Name"], "private-")
  }
}