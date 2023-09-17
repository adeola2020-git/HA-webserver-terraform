### Deploy a Highly Available Web Server on AWS ###
# We are creating the following resources vpc, subnets, IGW, RT,
#  RT Association, SG, ALB, Listeners, Target Group, Launch Template, ASG, Userdata,

# Define the provider
provider "aws" {
  region = var.region
}

# Define the VPC
resource "aws_vpc" "HA-VPC" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "HA-VPC"
  }
}

# Define the Internet Gateway
resource "aws_internet_gateway" "HA-IGW" {
  vpc_id = aws_vpc.HA-VPC.id

  tags = {
    Name = "HA-IGW"
  }
}

# Define 2 subnets in 2 AZs for HA
# Define the first Public Subnet
resource "aws_subnet" "HA-Public-Subnet1" {
  vpc_id                  = aws_vpc.HA-VPC.id
  cidr_block              = var.cidr_subnet1
  availability_zone       = var.availability_zone1
  map_public_ip_on_launch = true

  tags = {
    Name = "HA-Public-Subnet1"
  }
}

# Define the Second Public Subnet
resource "aws_subnet" "HA-Public-Subnet2" {
  vpc_id                  = aws_vpc.HA-VPC.id
  cidr_block              = var.cidr_subnet2
  availability_zone       = var.availability_zone2
  map_public_ip_on_launch = true

  tags = {
    Name = "HA-Public-Subnet2"
  }
}

# Define a Route Table
resource "aws_route_table" "HA-RT" {
  vpc_id = aws_vpc.HA-VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.HA-IGW.id
  }

  tags = {
    Name = "HA-RT"
  }
}

# Define an AWS Route Table Association with the first Public Subnet
resource "aws_route_table_association" "HA-rt1" {
  subnet_id      = aws_subnet.HA-Public-Subnet1.id
  route_table_id = aws_route_table.HA-RT.id
}

# Define an AWS Route Table Association with the 2nd Public Subnet
resource "aws_route_table_association" "HA-rt2" {
  subnet_id      = aws_subnet.HA-Public-Subnet2.id
  route_table_id = aws_route_table.HA-RT.id
}

# Define the security groups for the ALB
resource "aws_security_group" "HA-ALB-SG" {
  name        = "High-Availability-Security-Group"
  description = "High-Availability-Security-Group"
  vpc_id      = aws_vpc.HA-VPC.id

  # Inbound rules
  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Rules
  # Internet Access to Anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HA-ALB-SG"
  }
}

# Define an Application Load Balancer
resource "aws_alb" "HA-ALB" {
  name                       = "HA-ALB"
  subnets                    = [aws_subnet.HA-Public-Subnet1.id, aws_subnet.HA-Public-Subnet2.id]
  security_groups            = [aws_security_group.HA-ALB-SG.id]
  internal                   = false
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  enable_deletion_protection = false
  tags = {
    Name = "HA-ALB"
  }
}

# Define a Listener for the ALB
resource "aws_alb_listener" "HA-ALB-L" {
  load_balancer_arn = aws_alb.HA-ALB.arn
  port              = "80"
  protocol          = "HTTP"
  default_action { # This is a config block for default actions
    type             = "forward"
    target_group_arn = aws_alb_target_group.HA-ALB-TG.arn
  }
  tags = {
    Name = "HA-ALB-L"
  }
}

# Define a Target Group for the ALB
resource "aws_alb_target_group" "HA-ALB-TG" {
  name     = "HA-ALB-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.HA-VPC.id
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
  tags = {
    Name = "HA-ALB-TG"
  }
}

# Define a launch template
resource "aws_launch_template" "HA-LT" {
  name                   = "HA-LT"
  instance_type          = var.instance_type
  vpc_security_group_ids = ["${aws_security_group.HA-ALB-SG.id}"]
  user_data              = filebase64("userdata.sh")
  image_id               = var.image_id
  key_name               = var.key_name
  tags = {
    Name = "HA-LT"
  }
}

# Define an Auto Scaling Group
resource "aws_autoscaling_group" "HA-ASG" {
  name                      = "HA-ASG"
  max_size                  = 2
  desired_capacity          = 2
  min_size                  = 2
  health_check_grace_period = 300
  vpc_zone_identifier       = [aws_subnet.HA-Public-Subnet1.id, aws_subnet.HA-Public-Subnet2.id]
  health_check_type         = "EC2"
  target_group_arns         = [aws_alb_target_group.HA-ALB-TG.arn]
  launch_template {
    id      = aws_launch_template.HA-LT.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "HA-WEB-APP"
    propagate_at_launch = true
  }
}

