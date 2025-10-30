variable "aws_region" {
  type    = string
  default = "ap-south-2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type    = string
  default = "exemplifi-wp"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your IP in CIDR, e.g. 203.0.113.45/32"
}

variable "use_eip" {
  type    = bool
  default = true # optional: allocate Elastic IP
}
variable "ami_id" {
  default = "ami-0bd4cda58efa33d23"
}

variable "vpc_id" {
  default = "vpc-05c088c454d12c9e0"
}

variable "subnet_id" {
  default = "subnet-007be8f457ab5b0cb"
}
