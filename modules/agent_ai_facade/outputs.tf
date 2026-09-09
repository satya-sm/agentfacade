output "endpoint_service_name" {
  value       = aws_vpc_endpoint_service.facade_endpoint_service.service_name
  description = "PrivateLink Service Name to provide to vrm-sandbox"
}

output "facade_role_arn" {
  value       = aws_iam_role.facade_execution_role.arn
  description = "IAM Role ARN attached to the Façade"
}