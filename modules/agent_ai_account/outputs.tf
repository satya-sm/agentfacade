output "agent_runtime_arn" {
  value       = aws_bedrockagentcore_agent_runtime.runtime.arn
  description = "ARN of the AgentCore Runtime"
}

output "agent_runtime_endpoint_arn" {
  value       = aws_bedrockagentcore_agent_runtime_endpoint.runtime_endpoint.arn
  description = "ARN of the AgentCore Runtime Endpoint"
}

output "vpc_endpoint_id" {
  value       = aws_vpc_endpoint.bedrock_agentcore_vpce.id
  description = "Inbound PrivateLink Interface Endpoint ID"
}