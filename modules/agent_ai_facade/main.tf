# 1. IAM Execution Role for the Façade Microservice
resource "aws_iam_role" "facade_execution_role" {
  name = "AgentCoreFacadeExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "bedrock_access_policy" {
  name        = "AgentCoreBedrockAccessPolicy"
  description = "Allows Façade service to invoke Bedrock and AgentCore models"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockAgentCoreAccess"
        Effect   = "Allow"
        Action   = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock-agent-runtime:InvokeAgent"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "facade_bedrock_attach" {
  role       = aws_iam_role.facade_execution_role.name
  policy_arn = aws_iam_policy.bedrock_access_policy.arn
}

# 2. Target Group & Internal Network Load Balancer (NLB)
resource "aws_lb_target_group" "facade_tg" {
  name        = "agent-facade-tg"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.agent_ai_vpc_id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "8080"
  }
}

resource "aws_lb" "facade_nlb" {
  name               = "agent-facade-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.agent_ai_private_subnet_ids

  enable_deletion_protection = false
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

# 3. VPC Endpoint Service (PrivateLink Provider)
resource "aws_vpc_endpoint_service" "facade_endpoint_service" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.facade_nlb.arn]

  allowed_principals = [
    "arn:aws:iam::${var.vrm_sandbox_account_id}:root"
  ]

  tags = {
    Name = "agent-ai-facade-privatelink-service"
  }
}