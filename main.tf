locals {
  vpc_cidr_block     = "10.0.0.0/16"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  subnet_config      = zipmap(local.availability_zones, cidrsubnets(local.vpc_cidr_block, 1, 1))
  instance_config = {
    "federator" = {
      az                = local.availability_zones[0]
      enable_federation = true
    },
    "downstream" = {
      az                = local.availability_zones[1]
      enable_federation = false
    },
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

### VPC configuration ###
resource "aws_vpc" "this" {
  cidr_block           = local.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "public" {
  for_each = local.subnet_config

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route" "public_igw" {
  route_table_id = aws_route_table.public.id

  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

### Prometheus configuration ###
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_iam_instance_profile" "prometheus" {
  name = "prometheus"
  role = aws_iam_role.prometheus.name
}

data "aws_iam_policy_document" "prometheus" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "prometheus_scrape" {
  statement {
    actions   = ["ec2:DescribeInstances", "ec2:DescribeAvailabilityZones"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "prometheus" {
  name               = "prometheus"
  assume_role_policy = data.aws_iam_policy_document.prometheus.json

  inline_policy {
    name   = "prometheus-scrape"
    policy = data.aws_iam_policy_document.prometheus_scrape.json
  }
}

resource "aws_security_group" "prometheus" {
  vpc_id = aws_vpc.this.id
  name   = "prometheus"
}

resource "aws_security_group_rule" "ingress_ssh" {
  security_group_id = aws_security_group.prometheus.id
  description       = "SSH"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ingress_node_exporter" {
  security_group_id = aws_security_group.prometheus.id
  description       = "Prometheus node_exporter"
  type              = "ingress"
  from_port         = 9100
  to_port           = 9100
  protocol          = "tcp"
  self              = true
}

resource "aws_security_group_rule" "ingress_prometheus" {
  security_group_id = aws_security_group.prometheus.id
  description       = "Prometheus server"
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "egress" {
  security_group_id = aws_security_group.prometheus.id
  description       = "Allow all egress"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_network_interface" "prometheus" {
  for_each = local.instance_config

  subnet_id       = aws_subnet.public[each.value.az].id
  security_groups = [aws_security_group.prometheus.id]
}

resource "tls_private_key" "prometheus" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "prometheus" {
  public_key = tls_private_key.prometheus.public_key_openssh
}

resource "aws_instance" "prometheus" {
  for_each = local.instance_config

  ami                  = data.aws_ami.ubuntu_2204.id
  instance_type        = "t3.micro"
  user_data            = data.cloudinit_config.prometheus[each.key].rendered
  iam_instance_profile = aws_iam_instance_profile.prometheus.name
  key_name             = aws_key_pair.prometheus.key_name

  network_interface {
    network_interface_id = aws_network_interface.prometheus[each.key].id
    device_index         = 0
  }

  tags = {
    name = "prometheus"
  }
}

data "cloudinit_config" "prometheus" {
  for_each = local.instance_config

  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init-base.tftpl", {
      prometheus_version    = var.prometheus_version,
      node_exporter_version = var.node_exporter_version,
    })
  }

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init-prometheus-config.tftpl", {
      hostname          = aws_network_interface.prometheus[each.key].private_dns_name
      enable_federation = each.value.enable_federation
    })
  }
}

output "prometheus_federator_url" {
  value = "http://${aws_instance.prometheus["federator"].public_dns}:9090"
}

output "prometheus_downstream_url" {
  value = "http://${aws_instance.prometheus["downstream"].public_dns}:9090"
}

output "ssh_private_key" {
  sensitive = true
  value = tls_private_key.prometheus.private_key_openssh
}
