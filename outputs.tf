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

output "security_group_id" {
  description = "Security Group ID for the DevOps server"
  value       = aws_security_group.devops_ec2_sg.id
}

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.devops_server.id
}

output "deployment_status_check" {
  description = "Command to check deployment status"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.devops_server.public_ip} 'cat /home/ubuntu/deployment-status.txt'"
}

output "service_logs_commands" {
  description = "Commands to check service logs"
  value = {
    jenkins    = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.devops_server.public_ip} 'sudo docker logs jenkins'"
    sonarqube  = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.devops_server.public_ip} 'sudo docker logs sonarqube'"
    app_logs   = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.devops_server.public_ip} 'cd /home/ubuntu/amazon-clone && sudo docker compose -f docker-compose.prod.yml logs'"
  }
}