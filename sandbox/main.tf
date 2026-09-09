# In agent-ai environment pipeline
module "agent_ai_facade" {
  source = "./modules/agent_ai_facade"

  agent_ai_vpc_id             = "vpc-0123456789agentai"
  agent_ai_private_subnet_ids = ["subnet-0a1b2c3d4e5f", "subnet-0f5e4d3c2b1a"]
  vrm_sandbox_account_id      = "123456789012" # Account ID of vrm-sandbox
}

# In vrm-sandbox environment pipeline
module "vrm_sandbox" {
  source = "./modules/vrm_sandbox"

  vrm_sandbox_vpc_id                = "vpc-0987654321vrm"
  vrm_sandbox_private_subnet_ids    = ["subnet-1a2b3c4d", "subnet-4d3c2b1a"]
  eks_worker_node_security_group_id = "sg-0123456789eks"
  eks_pod_execution_role_name       = "EKSWorkerPodRole"
  privatelink_service_name          = module.agent_ai_facade.endpoint_service_name
}