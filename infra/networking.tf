resource "aws_security_group" "wp" {
  name        = "exemplifi-wp-sg"
  description = "Web (80/443) and restricted SSH (2222)"
  vpc_id      = var.vpc_id

  # HTTP & HTTPS open to world
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH only from YOUR IP on port 2222
  ingress {
    description = "SSH"
    from_port   = 2222
    to_port     = 2222
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # Egress all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Key pair from your local public key file
resource "aws_key_pair" "wp" {
  key_name   = var.key_name
  public_key = file("${path.module}/../exemplifi-wp.pub")
}
