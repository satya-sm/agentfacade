variable "app_vpc_id" {
  type        = string
  description = "Existing App VPC ID in vrm-sandbox"
}

variable "agent_account_id" {
  type        = string
  description = "AWS Account ID for vrm-ai (Agent Account)"
}

variable "internal_alb_arn" {
  type        = string
  description = "ARN of existing internal ALB (internal-agent-tools.internal.smarshvrm.com)"
}

variable "internal_alb_dns_name" {
  type        = string
  description = "DNS name of the existing internal ALB"
}