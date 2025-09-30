# Output values for the DevOps infrastructure

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.devops_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.devops_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.devops_server.private_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.devops_server.public_dns
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.devops_sg.id
}

output "jenkins_url" {
  description = "URL to access Jenkins"
  value       = "http://${aws_instance.devops_server.public_ip}:8080"
}

output "sonarqube_url" {
  description = "URL to access SonarQube"
  value       = "http://${aws_instance.devops_server.public_ip}:9000"
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.devops_server.public_ip}"
}

output "services_status_command" {
  description = "Command to check services status via SSH"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.devops_server.public_ip} 'sudo systemctl status jenkins sonarqube docker'"
}

output "minikube_dashboard_command" {
  description = "Command to access Minikube dashboard (run on the instance)"
  value       = "kubectl proxy --address='0.0.0.0' --disable-filter=true"
}
