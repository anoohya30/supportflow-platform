# A small private network (VPC) with one public subnet for the lab host.
# Single subnet / single AZ is a deliberate cost compromise (see decisions).

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "supportflow-vpc" }
}

# Lock down the VPC's automatic "default" security group (no rules = no traffic).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "supportflow-default-sg-locked" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "supportflow-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "supportflow-public-a" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "supportflow-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Firewall for the lab host.
# ONLY port 80 (the app, via the k3s ingress) is open to the internet.
# No SSH (22), no Kubernetes API (6443), no database (5432):
# admin access is through AWS Session Manager, an authenticated tunnel.
resource "aws_security_group" "host" {
  name        = "supportflow-host"
  description = "SupportFlow lab host: app ingress on 80 only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "supportflow-host-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.app_ingress_cidrs)

  security_group_id = aws_security_group.host.id
  description       = "App ingress (HTTP) via k3s Traefik"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

# Outbound: needed to install k3s/Helm, pull images from ECR,
# and talk to Session Manager.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.host.id
  description       = "Outbound internet (packages, ECR, SSM)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
