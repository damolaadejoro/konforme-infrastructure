# --- Elastic IP ---

resource "aws_eip" "main" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-eip"
  }
}

resource "aws_eip_association" "main" {
  instance_id   = aws_instance.main.id
  allocation_id = aws_eip.main.id
}

# --- EC2 Instance ---

resource "aws_instance" "main" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    aws_region   = var.aws_region
    project_name = var.project_name
    ecr_repo_url = aws_ecr_repository.backend.repository_url
    api_fqdn     = local.api_fqdn
    data_device  = "/dev/xvdf"
  }))

  tags = {
    Name = "${local.name_prefix}-server"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# --- Separate EBS Volume for Postgres Data ---

resource "aws_ebs_volume" "postgres_data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${local.name_prefix}-postgres-data"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "postgres_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.postgres_data.id
  instance_id = aws_instance.main.id

  # Don't destroy volume on detach
  force_detach = false
}
