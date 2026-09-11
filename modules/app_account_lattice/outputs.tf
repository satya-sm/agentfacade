output "vpclattice_service_arn" {
  value       = aws_vpclattice_service.agent_tools_service.arn
  description = "ARN of the VPC Lattice Service exposing Rails API tools"
}

output "ram_resource_share_arn" {
  value       = aws_ram_resource_share.lattice_ram_share.arn
  description = "RAM Resource Share ARN exposing Lattice configuration to vrm-ai"
}