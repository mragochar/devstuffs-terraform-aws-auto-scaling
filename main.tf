# -----------------------
# VPC
# -----------------------
# vpc definition
resource "aws_vpc" "auto_scaling" {
  cidr_block       = var.cidr
  instance_tenancy = "default"

  tags = {
    Name      = var.vpc_name
    Terraform = true
  }
}

# add internet gateway to vpc
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.auto_scaling.id

  tags = {
    Name      = "${var.vpc_name}-igw"
    Terraform = true
  }
}

resource "aws_vpc_security_group_vpc_association" "ssh_http_allow" {
  security_group_id = var.security_group_id
  vpc_id            = aws_vpc.auto_scaling.id
}


# -----------------------
# Subnets
# -----------------------

# private and public subnets in ap-south-1a
resource "aws_subnet" "subnets_az_1a" {
  vpc_id = aws_vpc.auto_scaling.id

  for_each = var.subnets_az_1a

  availability_zone       = var.availability_zones["az_1a"] # ap-south-1a
  map_public_ip_on_launch = startswith(each.key, "public-") # true if subnet is public

  cidr_block = each.value

  tags = {
    Name      = each.key
    Terraform = true
  }
}

# private and public subnets in ap-south-1a
resource "aws_subnet" "subnets_az_1b" {
  vpc_id = aws_vpc.auto_scaling.id

  for_each = var.subnets_az_1b

  availability_zone       = var.availability_zones["az_1b"] # ap-south-1b
  map_public_ip_on_launch = startswith(each.key, "public-") # true if subnet is public

  cidr_block = each.value

  tags = {
    Name      = each.key
    Terraform = true
  }
}

# -----------------------
# NAT Gateways
# -----------------------
# allocate eip
resource "aws_eip" "ngw" {
  for_each = local.public_subnets

  domain = "vpc"

  tags = {
    Name      = "ngw-${each.key}"
    Terraform = true
  }
}

# ngws for private subnets (ngw itself be on public subnets)
resource "aws_nat_gateway" "ngw" {
  for_each = local.public_subnets

  allocation_id = aws_eip.ngw[each.key].id
  subnet_id     = each.value

  tags = {
    Name      = "ngw-${each.key}"
    Terraform = true
  }

  depends_on = [aws_internet_gateway.igw]
}


# -----------------------
# Route Tables
# -----------------------
# define route tables
resource "aws_route_table" "all" {
  vpc_id = aws_vpc.auto_scaling.id

  for_each = toset(local.route_table_names)

  tags = {
    Name      = each.key
    Terraform = true
  }
}

# add routes to above route tables (only for public route tables)
resource "aws_route" "public_routes" {
  for_each = {
    for key, route_table in aws_route_table.all :
    key => route_table
    if startswith(key, "rt-public-")
  }

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# associate above route tables to (public only)
resource "aws_route_table_association" "public" {
  for_each = local.public_subnets_route_tables

  subnet_id      = merge(
    aws_subnet.subnets_az_1a,
    aws_subnet.subnets_az_1b
  )[each.key].id

  route_table_id = each.value
}

# add routes to above route tables (only for private route tables)
resource "aws_route" "private_routes" {
  for_each = {
    for key, rtb in aws_route_table.all :
    key => rtb
    if startswith(key, "rt-private-")
  }

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = aws_nat_gateway.ngw[
    replace(each.key, "rt-private-", "public-")
  ].id
}

# associate above route tables to (public only)
resource "aws_route_table_association" "private" {
  for_each = local.private_subnets_route_tables

  subnet_id      = merge(
    aws_subnet.subnets_az_1a,
    aws_subnet.subnets_az_1b
  )[each.key].id

  route_table_id = each.value
}

# -----------------------
# Launch Template
# -----------------------
resource "aws_launch_template" "example" {
  name = var.launch_template_name

  # ami 
  image_id = "ami-01a00762f46d584a1" # ubuntu AMI copied after searching (not from data block)

  # instance settings (could have defined cpu settings but it's enough)
  instance_type = "t3.nano"

  # ssh key 
  key_name = "ec2-key" # managed outside Terraform (already created)

  # networking details 
  vpc_security_group_ids = [aws_vpc_security_group_vpc_association.ssh_http_allow.security_group_id] # managed outside Terraform

  # storage
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # tags
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name      = var.launch_template_name
      Terraform = true
    }
  }

  # advanced settings (only user_data)
  user_data = filebase64("${path.module}/user_data.sh")
}


# -----------------------
# Target Group (Instance)
# -----------------------
resource "aws_lb_target_group" "test" {
  # immutable settings
  name        = "tg-${var.vpc_name}"
  target_type = "instance" # default
  vpc_id      = aws_vpc.auto_scaling.id
  port        = 80
  protocol    = "HTTP"
  # default health check yet defined to be specific
  health_check {
    enabled = true
    path    = "/"
  }
  # mutable settings
  tags = {
    Name      = "tg-${var.vpc_name}"
    Terraform = true
  }
}


# -----------------------
# Load Balancers
# ----------------------
# define alb 
resource "aws_lb" "auto_scaling" {
  name               = "alb-${var.vpc_name}"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_vpc_security_group_vpc_association.ssh_http_allow.security_group_id] # managed outside Terraform
  subnets            = values(local.public_subnets)
  ip_address_type    = "ipv4"

  tags = {
    Name      = "alb-${var.vpc_name}"
    Terraform = true
  }
}

# define listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.auto_scaling.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}

# -----------------------
# Auto Scaling Groups
# ----------------------
resource "aws_autoscaling_group" "front_end" {
  name                = "asg-web-app"
  vpc_zone_identifier = values(local.private_subnets)
  desired_capacity    = 2
  max_size            = 2
  min_size            = 2
  target_group_arns   = [aws_lb_target_group.test.arn]

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "asg-web-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Terraform"
    value               = true
    propagate_at_launch = true
  }
}