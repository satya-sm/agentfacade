# ==============================================================================
# 1. SECURITY GROUPS & DENY-BY-DEFAULT EGRESS
# ==============================================================================

resource "aws_security_group" "agentcore_sg" {
  name        = "agentcore-runtime-sg"
  description = "Strict SG for AgentCore runtime execution"
  vpc_id      = var.agent_vpc_id

  # Inbound traffic permitted via PrivateLink
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Egress restricted to internal VPC & Lattice paths
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  tags = {
    Name        = "vrm-ai-agentcore-sg"
    Environment = "production"
  }
}

# ==============================================================================
# 2. AGENTCORE RUNTIME & IAM EXECUTION ROLE
# ==============================================================================

resource "aws_iam_role" "agentcore_execution_role" {
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

resource "aws_iam_policy" "agentcore_policy" {
  name = "AgentCoreMinimalExecutionPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowBedrockConverseOnly"
        Effect   = "Allow"
        Action   = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "agentcore_attach" {
  role       = aws_iam_role.agentcore_execution_role.name
  policy_arn = aws_iam_policy.agentcore_policy.arn
}

resource "aws_bedrockagentcore_agent_runtime" "runtime" {
  agent_runtime_name = "vrm-ai-agent-runtime"
  description        = "Ephemeral microVM runtime for AutoAssess and AI Reviewer"
  role_arn           = aws_iam_role.agentcore_execution_role.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = var.container_image_uri
    }
  }

  managed_vpc_resource {
    vpc_identifier           = var.agent_vpc_id
    subnet_ids               = var.agent_private_subnet_ids
    security_group_ids       = [aws_security_group.agentcore_sg.id]
    endpoint_ip_address_type = "IPV4"
  }
}

resource "aws_bedrockagentcore_agent_runtime_endpoint" "runtime_endpoint" {
  name             = "vrm-ai-runtime-endpoint"
  description      = "Private execution endpoint for AgentCore Runtime"
  agent_runtime_id = aws_bedrockagentcore_agent_runtime.runtime.agent_runtime_id
}

# ==============================================================================
# 3. AGENTCORE GATEWAY & CEDAR POLICY ENGINE
# ==============================================================================

resource "aws_bedrockagentcore_gateway" "gateway" {
  name        = "vrm-ai-agent-gateway"
  description = "Policy enforcement engine validating MCP tool calls"

  authorizer_configuration {
    type = "CEDAR"
  }
}

resource "aws_bedrockagentcore_gateway_policy" "mcp_tool_policy" {
  gateway_id  = aws_bedrockagentcore_gateway.gateway.id
  name        = "mcp-rails-tool-policy"
  description = "Cedar rules enforcing run-token constraints and per-session parameter validation"

  statement = <<-CEDAR
    permit (
      principal,
      action in [
        Action::"AgentTools::fetch_manifest",
        Action::"AgentTools::fetch_document",
        Action::"AgentTools::record_answer",
        Action::"AgentTools::finalize_run"
      ],
      resource
    )
    when {
      context.run_token.is_valid == true
    };
  CEDAR
}

# ==============================================================================
# 4. INBOUND PRIVATELINK ENDPOINT & DUAL RESOURCE POLICIES
# ==============================================================================

resource "aws_vpc_endpoint" "bedrock_agentcore_vpce" {
  vpc_id              = var.agent_vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agentcore"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.agent_private_subnet_ids
  security_group_ids  = [aws_security_group.agentcore_sg.id]
  private_dns_enabled = true
}

# Dual Resource Policy enforcing Sidekiq IRSA role AND specific VPC Endpoint
data "aws_iam_policy_document" "inbound_dual_policy" {
  statement {
    sid    = "AllowSidekiqIRSARoleOnly"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.sidekiq_irsa_role_arn]
    }
    actions   = ["bedrock-agentcore:InvokeAgentRuntime"]
    resources = [
      aws_bedrockagentcore_agent_runtime.runtime.arn,
      aws_bedrockagentcore_agent_runtime_endpoint.runtime_endpoint.arn
    ]
  }

  statement {
    sid    = "DenyRequestsNotFromSpecificVPCEndpoint"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["bedrock-agentcore:InvokeAgentRuntime"]
    resources = [
      aws_bedrockagentcore_agent_runtime.runtime.arn,
      aws_bedrockagentcore_agent_runtime_endpoint.runtime_endpoint.arn
    ]
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.bedrock_agentcore_vpce.id]
    }
  }
}