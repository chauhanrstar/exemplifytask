# Data source to fetch the latest Ubuntu LTS AMI
# This will search for Ubuntu 22.04 or 24.04 LTS AMIs published by Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-*22.04-amd64-server-*",
      "ubuntu/images/hvm-ssd/ubuntu-*24.04-amd64-server-*"
    ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
