variable "aws_region" { default = "us-east-1" }
variable "app_account_id" { default = "658921945294" }
variable "agent_account_id" { default = "025280097068" }

variable "existing_app_vpc_id" {
  type        = string
  description = "Existing VPC ID for Rails/EKS (App Account)"
}

variable "existing_agent_vpc_id" {
  type        = string
  description = "Existing VPC ID for Bedrock Agent (Agent Account)"
}

variable "existing_internal_alb_arn" {
  type        = string
  description = "ARN of internal-agent-tools ALB"
}

variable "existing_sidekiq_irsa_role_name" {
  type        = string
  description = "IAM Role Name used by Sidekiq pods"
}

variable "agent_runtime_image_uri" {
  type        = string
  description = "ECR Image URI for the agent container"
}