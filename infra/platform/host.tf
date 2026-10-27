# The single EC2 lab host running k3s (lightweight Kubernetes).
# One host is an intentional cost compromise: NOT highly available.

# Latest official Ubuntu 24.04 LTS image from Canonical.
data "aws_ami" "ubuntu" {
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

resource "aws_instance" "host" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.host.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name
  ebs_optimized          = true

  # First-boot script: installs k3s + Helm, creates the namespaces and the
  # ECR image-pull secret refresher. Log: /var/log/supportflow-bootstrap.log
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region       = var.region
    k3s_version  = var.k3s_version
    helm_version = var.helm_version
    ecr_registry = split("/", aws_ecr_repository.app.repository_url)[0]
  })
  user_data_replace_on_change = true

  # Metadata service hardening:
  #  - IMDSv2 only (token required)
  #  - hop limit 1: containers/pods cannot reach the metadata service,
  #    so they cannot borrow the host's AWS role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "supportflow-lab-host" }

  # Incident 2026-10-27 (docs/incident-2026-10-27-host-replaced.md): the AMI
  # data source picks the NEWEST Ubuntu image, so when Canonical published a
  # new image, an unrelated apply replaced the host and its disk. A new AMI
  # must never replace the running host by surprise: host rebuilds are a
  # deliberate, reviewed action (terraform apply -replace=aws_instance.host).
  lifecycle {
    ignore_changes = [ami]
  }
}

# Fixed public IP, so app URLs stay the same if the host is stopped/started.
resource "aws_eip" "host" {
  domain   = "vpc"
  instance = aws_instance.host.id
  tags     = { Name = "supportflow-host-ip" }

  depends_on = [aws_internet_gateway.main]
}
