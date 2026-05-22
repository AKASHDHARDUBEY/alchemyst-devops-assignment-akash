output "api_gateway_public_ip" {
  description = "Public IP of the API Gateway instance"
  value       = aws_instance.api_gateway.public_ip
}

output "api_gateway_private_ip" {
  description = "Private IP of the API Gateway instance"
  value       = aws_instance.api_gateway.private_ip
}

output "ts_worker_private_ip" {
  description = "Private IP of the TypeScript Worker instance"
  value       = aws_instance.ts_worker.private_ip
}

output "python_worker_private_ip" {
  description = "Private IP of the Python Worker instance"
  value       = aws_instance.python_worker.private_ip
}
