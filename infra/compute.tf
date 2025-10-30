resource "aws_instance" "wp" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  key_name               = aws_key_pair.wp.key_name
  vpc_security_group_ids = [aws_security_group.wp.id]

  user_data = file("${path.module}/cloud-init.sh")

  tags = {
    Name = "exemplifi-wp"
  }
}

# Optional Elastic IP (recommended for a stable public IP)
resource "aws_eip" "wp" {
  count    = var.use_eip ? 1 : 0
  instance = aws_instance.wp.id
  domain   = "vpc"
}
