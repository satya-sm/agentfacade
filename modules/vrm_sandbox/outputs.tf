output "vpc_endpoint_id" {
  value       = aws_vpc_endpoint.facade_endpoint.id
  description = "VPC Endpoint ID in vrm-sandbox"
}

output "vpc_endpoint_dns_entries" {
  value       = aws_vpc_endpoint.facade_endpoint.dns_entry
  description = "DNS targets for application code calls"
}