#############################################
# main.tf — Ubuntu 24.04 for master & agent
#############################################

provider "aws" {
  region = "us-east-1"
}

# --- Puppet Forge API Key
# This is needed to install Puppet modules from the Forge.
variable "puppet_api_key" {
  description = "Puppet Forge API Key"
  type        = string
  sensitive   = true
}

# --- Userdata for Puppet repo packages setup
# This script configures the Puppet repository on the instance.
locals {
  puppet_repo_userdata = <<-EOF
    #!/bin/bash
    set -e

    API_KEY="${var.puppet_api_key}"

    apt-get update -y
    apt-get install -y wget gnupg

    wget --content-disposition https://apt-puppetcore.puppet.com/public/puppet8-release-noble.deb
    dpkg -i puppet8-release-noble.deb

    cat >/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf <<EOC
    machine apt-puppetcore.puppet.com
    login forge-key
    password $API_KEY
    EOC

    chmod 600 /etc/apt/auth.conf.d/apt-puppetcore-puppet.conf

    echo "Puppet repo configured. Run 'sudo apt-get install -y <puppertserver OR puppet-agent>' manually." > readme.txt
  EOF
}

# --- Networking (public subnet + IGW + public route)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "puppet-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "puppet-public-subnet" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "puppet-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = { Name = "puppet-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group (no host firewall; allow SSH + Puppet)
resource "aws_security_group" "puppet" {
  name        = "puppet-sg"
  description = "Allow SSH (22) and Puppet (8140)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Puppet Server"
    from_port   = 8140
    to_port     = 8140
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "puppet-sg" }
}

# Allow HTTP only for the agent
resource "aws_security_group" "agent_http" {
  name        = "puppet-agent-http"
  description = "Allow HTTP (80) to the agent only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "puppet-agent-http" }
}


# --- Ubuntu 24.04 LTS AMI (Canonical)
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Instances
# Puppet Master (t3.medium for better performance)
resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "t3.medium" # t3.medium for better performance and needed RAM
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.puppet.id]
  associate_public_ip_address = true
  user_data                   = local.puppet_repo_userdata

  tags = { Name = "puppet-master" }
}

# Puppet Agent (t3.micro is sufficient for agent tasks)
# Attach the base Puppet SG + the HTTP SG for agent HTTP access
resource "aws_instance" "agent" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [
    aws_security_group.puppet.id,
    aws_security_group.agent_http.id
  ]
  associate_public_ip_address = true
  user_data                   = local.puppet_repo_userdata
  
  tags = { Name = "puppet-agent" }
}

# --- Helpful outputs
output "master_public_ip"   { value = aws_instance.master.public_ip }
output "agent_public_ip"    { value = aws_instance.agent.public_ip }
output "master_private_ip"  { value = aws_instance.master.private_ip }
