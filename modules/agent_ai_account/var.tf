variable "agent_vpc_id" {
  type        = string
  description = "Existing Agent VPC ID in vrm-ai"
}

variable "agent_private_subnet_ids" {
  type        = list(string)
  description = "Existing Agent private subnet IDs (no IGW/NAT)"
}

variable "app_account_id" {
  type        = string
  description = "AWS Account ID for vrm-sandbox (App Account)"
}

variable "sidekiq_irsa_role_arn" {
  type        = string
  description = "ARN of existing EKS Sidekiq IAM role in App Account"
}

variable "container_image_uri" {
  type        = string
  description = "ECR Image URI for the Agent Runtime container"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}