# Output values for dev-project-jen-k8-min infrastructure

output "instance_id" {
  description = "ID of the dev-project-jen-k8-min EC2 instance"
  value       = aws_instance.dev_project_instance.id
}

output "instance_name" {
  description = "Name of the EC2 instance"
  value       = "dev-project-jen-k8-min"
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.dev_project_instance.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.dev_project_instance.private_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.dev_project_instance.public_dns
}

output "instance_type" {
  description = "Type of the EC2 instance"
  value       = aws_instance.dev_project_instance.instance_type
}

output "ami_id" {
  description = "AMI ID used for the instance (Amazon Linux 2023 kernel 6.1)"
  value       = aws_instance.dev_project_instance.ami
}

output "key_pair_name" {
  description = "Name of the key pair used for the instance"
  value       = aws_instance.dev_project_instance.key_name
}

output "security_group_id" {
  description = "ID of the security group (launch-wizard-6)"
  value       = data.aws_security_group.existing_sg.id
}

output "security_group_name" {
  description = "Name of the security group"
  value       = data.aws_security_group.existing_sg.name
}

output "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  value       = aws_instance.dev_project_instance.root_block_device[0].volume_size
}

output "jenkins_url" {
  description = "URL to access Jenkins web interface"
  value       = "http://${aws_instance.dev_project_instance.public_ip}:8080"
}

output "sonarqube_url" {
  description = "URL to access SonarQube web interface"
  value       = "http://${aws_instance.dev_project_instance.public_ip}:9000"
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip}"
}

output "docker_status_command" {
  description = "Command to check Docker status"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip} 'sudo systemctl status docker'"
}

output "jenkins_status_command" {
  description = "Command to check Jenkins status"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip} 'sudo systemctl status jenkins'"
}

output "sonarqube_status_command" {
  description = "Command to check SonarQube status"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip} 'sudo systemctl status sonarqube'"
}

output "kubernetes_status_command" {
  description = "Command to check Kubernetes/Minikube status"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip} 'minikube status && kubectl get nodes'"
}

output "all_services_status_command" {
  description = "Command to check all services status via SSH"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip} 'sudo systemctl status docker jenkins sonarqube && minikube status'"
}

output "jenkins_initial_password_command" {
  description = "Command to get Jenkins initial admin password"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip} 'cat ~/jenkins_initial_password.txt'"
}

output "minikube_dashboard_command" {
  description = "Command to access Minikube dashboard (run on the instance)"
  value       = "minikube dashboard --url"
}

output "service_info_file_command" {
  description = "Command to view service information file"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.dev_project_instance.public_ip} 'cat ~/service_info.txt'"
}

output "default_credentials" {
  description = "Default service credentials"
  value = {
    jenkins_user     = "admin"
    jenkins_password = "Check ~/jenkins_initial_password.txt on the instance"
    sonarqube_user   = "admin" 
    sonarqube_password = "admin"
  }
  sensitive = false
}
