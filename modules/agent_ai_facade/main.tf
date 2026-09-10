# ==============================================================================
# 1. BEDROCK KNOWLEDGE BASE & GUARDRAILS
# ==============================================================================

resource "aws_bedrock_guardrail" "central_guardrail" {
  name        = "agentcore-central-guardrail"
  description = "Filters prompt attacks, PII, and sensitive topics"

  blocked_input_messaging   = "Request blocked by central security policy."
  blocked_outputs_messaging = "Response blocked by central security policy."

  content_policy_config {
    filters_config {
      type           = "PROMPT_ATTACK"
      input_strength = "HIGH"
      output_strength = "NONE"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
  }
}

resource "aws_iam_role" "kb_role" {
  name = "AgentCoreKnowledgeBaseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "kb_policy" {
  name = "AgentCoreKnowledgeBasePolicy"
  role = aws_iam_role.kb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_bedrockagent_knowledge_base" "agentcore_kb" {
  name     = "agentcore-knowledge-base"
  role_arn = aws_iam_role.kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v1"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = var.opensearch_collection_arn
      vector_index_name = "agentcore-index"
      field_mapping {
        vector_field         = "bedrock-knowledge-base-default-vector"
        text_field           = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field       = "AMAZON_BEDROCK_METADATA"
      }
    }
  }
}

# ==============================================================================
# 2. AGENTCORE NATIVE MEMORY RESOURCE
# ==============================================================================

resource "aws_bedrockagentcore_memory" "agentcore_memory" {
  name                  = "agentcore-session-memory"
  description           = "Persistent contextual memory for agent runtime interactions"
  event_expiry_duration = 30 # Days before events expire

  indexed_key {
    key  = "session_id"
    type = "STRING"
  }

  tags = {
    Environment = "agent-ai"
    Component   = "AgentCore-Memory"
  }
}

# ==============================================================================
# 3. AGENTCORE RUNTIME & AGENTCORE RUNTIME ENDPOINT
# ==============================================================================

resource "aws_ecr_repository" "agent_code_repo" {
  name                 = "agentcore-runtime-container"
  image_tag_mutability = "MUTABLE"
}

# IAM Role assumed by the AgentCore Runtime
resource "aws_iam_role" "agentcore_runtime_role" {
  name = "AgentCoreRuntimeExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "agentcore_runtime_policy" {
  name = "AgentCoreRuntimeAccessPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockAndKBAccess"
        Effect   = "Allow"
        Action   = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
          "bedrock:ApplyGuardrail"
        ]
        Resource = "*"
      },
      {
        Sid      = "AgentCoreMemoryAccess"
        Effect   = "Allow"
        Action   = [
          "bedrock-agentcore:SaveMemoryEvent",
          "bedrock-agentcore:GetMemoryEvent",
          "bedrock-agentcore:ListMemoryEvents"
        ]
        Resource = aws_bedrockagentcore_memory.agentcore_memory.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "agentcore_runtime_attach" {
  role       = aws_iam_role.agentcore_runtime_role.name
  policy_arn = aws_iam_policy.agentcore_runtime_policy.arn
}

# Native AgentCore Agent Runtime
resource "aws_bedrockagentcore_agent_runtime" "agentcore_runtime" {
  agent_runtime_name = "agentcore-app-runtime"
  description        = "Containerized AgentCore agent with memory and knowledge base"
  role_arn           = aws_iam_role.agentcore_runtime_role.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agent_code_repo.repository_url}:latest"
    }
  }

  environment_variables = {
    BEDROCK_KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.agentcore_kb.id
    BEDROCK_GUARDRAIL_ID      = aws_bedrock_guardrail.central_guardrail.id
    AGENTCORE_MEMORY_ID       = aws_bedrockagentcore_memory.agentcore_memory.id
    AWS_REGION_NAME           = var.aws_region
  }

  managed_vpc_resource {
    vpc_identifier           = var.agent_ai_vpc_id
    subnet_ids               = var.agent_ai_private_subnet_ids
    security_group_ids       = [aws_security_group.agentcore_runtime_sg.id]
    endpoint_ip_address_type = "IPV4"
  }
}

resource "aws_security_group" "agentcore_runtime_sg" {
  name        = "agentcore-runtime-sg"
  description = "Security group attached to AgentCore Runtime VPC Interface"
  vpc_id      = var.agent_ai_vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Native AgentCore Agent Runtime Endpoint
resource "aws_bedrockagentcore_agent_runtime_endpoint" "agentcore_runtime_endpoint" {
  name             = "agentcore-prod-endpoint"
  description      = "Production network endpoint for AgentCore agent execution"
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.agentcore_runtime.agent_runtime_id
}

# ==============================================================================
# 4. NETWORK FAÇADE & PRIVATELINK EXPOSURE LAYER
# ==============================================================================

# Target group pointing to AgentCore Runtime Endpoint
resource "aws_lb_target_group" "facade_tg" {
  name        = "agentcore-target-group"
  port        = 443
  protocol    = "TCP"
  vpc_id      = var.agent_ai_vpc_id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "443"
  }
}

# ==============================================================================
# TARGET GROUP ATTACHMENT TO AGENTCORE RUNTIME ENDPOINT INTERFACE ENIs
# ==============================================================================

# Fetch the Network Interfaces (ENIs) automatically generated by the AgentCore Runtime
data "aws_network_interface" "agentcore_runtime_enis" {
  for_each = toset(var.agent_ai_private_subnet_ids)

  filter {
    name   = "vpc-id"
    values = [var.agent_ai_vpc_id]
  }

  filter {
    name   = "subnet-id"
    values = [each.value]
  }

  filter {
    name   = "description"
    values = ["*bedrockagentcore*${aws_bedrockagentcore_agent_runtime.agentcore_runtime.agent_runtime_id}*"]
  }
}

# Attach the private IP of each ENI to the NLB Target Group
resource "aws_lb_target_group_attachment" "agentcore_runtime_attachment" {
  for_each         = data.aws_network_interface.agentcore_runtime_enis
  target_group_arn = aws_lb_target_group.facade_tg.arn
  target_id        = each.value.private_ip
  port             = 443
}

resource "aws_lb" "facade_nlb" {
  name               = "agentcore-facade-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.agent_ai_private_subnet_ids
}

resource "aws_lb_listener" "facade_listener" {
  load_balancer_arn = aws_lb.facade_nlb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.facade_tg.arn
  }
}

resource "aws_vpc_endpoint_service" "facade_endpoint_service" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.facade_nlb.arn]

  allowed_principals = [
    "arn:aws:iam::${var.vrm_sandbox_account_id}:root"
  ]

  tags = {
    Name = "agentcore-privatelink-service"
  }
}