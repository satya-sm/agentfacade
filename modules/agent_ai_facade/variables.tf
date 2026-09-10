variable "agent_ai_vpc_id" {
  type        = string
  description = "VPC ID of the agent-ai account"
}

variable "agent_ai_private_subnet_ids" {
  type        = list(string)
  description = "Private Subnet IDs where NLB will be placed"
}

variable "vrm_sandbox_account_id" {
  type        = string
  description = "AWS Account ID of vrm-sandbox"
}