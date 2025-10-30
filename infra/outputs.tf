output "instance_public_ip" {
  description = "The public IP of the WordPress instance"
  value       = aws_instance.wp.public_ip
}

output "elastic_ip" {
  description = "The Elastic IP address (if enabled)"
  value       = try(aws_eip.wp[0].public_ip, null)
}

output "ssh_hint" {
  description = "Command to SSH into the WordPress instance"
  value       = "ssh -i ../exemplifi-wp -p 2222 ubuntu@${try(aws_eip.wp[0].public_ip, aws_instance.wp.public_ip)}"
}
