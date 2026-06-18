output "instance_public_ip" {
  value       = aws_instance.security_lab_node.public_ip
  description = "The public IP address of the EC2 instance"
}

output "ssh_command" {
  value       = "ssh -i \"<PATH_TO_YOUR_KEY_PAIR_PEM_FILE>\" ubuntu@${aws_instance.security_lab_node.public_ip}"
  description = "SSH Command to connect to the EC2 instance"
}

output "argocd_url" {
  value       = "https://${aws_instance.security_lab_node.public_ip}:8443"
  description = "URL to access ArgoCD Web UI"
}
