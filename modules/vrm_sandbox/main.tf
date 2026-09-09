# 1. Block Direct Bedrock Access Policy for EKS Roles
resource "aws_iam_policy" "deny_bedrock_policy" {
  name        = "DenyDirectBedrockAccess"
  description = "Explicitly denies direct access to Amazon Bedrock resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BlockDirectBedrockAccess"
        Effect   = "Deny"
        Action   = [
          "bedrock:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_deny_to_eks_role" {
  role       = var.eks_pod_execution_role_name
  policy_arn = aws_iam_policy.deny_bedrock_policy.arn
}

# 2. Security Group for Interface VPC Endpoint
resource "aws_security_group" "vpce_sg" {
  name        = "agent-facade-vpce-sg"
  description = "Allow inbound traffic from EKS worker nodes to VPC Endpoint"
  vpc_id      = var.vrm_sandbox_vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.eks_worker_node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "agent-facade-vpce-sg"
  }
}

# 3. Interface VPC Endpoint (Consumer)
resource "aws_vpc_endpoint" "facade_endpoint" {
  vpc_id              = var.vrm_sandbox_vpc_id
  service_name        = var.privatelink_service_name
  vpc_endpoint_type   = "Interface"

  subnet_ids          = var.vrm_sandbox_private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_sg.id]

  private_dns_enabled = false

  tags = {
    Name = "agent-ai-facade-endpoint"
  }
}