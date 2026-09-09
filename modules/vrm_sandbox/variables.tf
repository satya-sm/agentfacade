variable "vrm_sandbox_vpc_id" {
  type        = string
  description = "VPC ID of vrm-sandbox account"
}

variable "vrm_sandbox_private_subnet_ids" {
  type        = list(string)
  description = "Private Subnet IDs where VPC Endpoint will be placed"
}

variable "eks_worker_node_security_group_id" {
  type        = string
  description = "Security Group ID attached to EKS worker nodes"
}

variable "eks_pod_execution_role_name" {
  type        = string
  description = "IAM Role name associated with EKS Pods / IRSA"
}

variable "privatelink_service_name" {
  type        = string
  description = "PrivateLink Endpoint Service name from agent-ai account"
}