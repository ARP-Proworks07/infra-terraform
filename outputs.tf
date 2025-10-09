output "public_ip" {
  description = "Public IP address of the devops server"
  value       = aws_instance.devops_server.public_ip
}

output "jenkins_url" {
  description = "URL to access Jenkins UI"
  value       = "http://${aws_instance.devops_server.public_ip}:8080"
}

output "sonarqube_url" {
  description = "URL to access SonarQube UI"
  value       = "http://${aws_instance.devops_server.public_ip}:9000"
}

output "amazon_clone_frontend_url" {
  description = "URL to access Amazon Clone Frontend"
  value       = "http://${aws_instance.devops_server.public_ip}:3000"
}

output "amazon_clone_backend_url" {
  description = "URL to access Amazon Clone Backend API"
  value       = "http://${aws_instance.devops_server.public_ip}:3001"
}

output "k3s_master_node" {
  description = "K3s master node internal IP"
  value       = aws_instance.devops_server.private_ip
}

output "ssh_connection" {
  description = "SSH connection command"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.devops_server.public_ip}"
}