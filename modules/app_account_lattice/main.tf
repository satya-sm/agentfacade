# ==============================================================================
# 1. VPC LATTICE TARGET GROUP & SERVICE CONFIGURATION
# ==============================================================================

resource "aws_vpclattice_target_group" "rails_alb_target_group" {
  name = "rails-internal-alb-target"
  type = "ALB"

  config {
    vpc_identifier = var.app_vpc_id
    port           = 443
    protocol       = "HTTPS"
  }
}

resource "aws_vpclattice_target_group_attachment" "alb_attachment" {
  target_group_identifier = aws_vpclattice_target_group.rails_alb_target_group.id
  target {
    id   = var.internal_alb_arn
    port = 443
  }
}

resource "aws_vpclattice_service" "agent_tools_service" {
  name      = "agent-tools-api"
  auth_type = "AWS_IAM"
}

resource "aws_vpclattice_listener" "https_listener" {
  name                = "https-listener"
  service_identifier  = aws_vpclattice_service.agent_tools_service.id
  protocol            = "HTTPS"
  port                = 443

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.rails_alb_target_group.id
      }
    }
  }
}

# Resource configuration for cross-account exposure
resource "aws_vpclattice_resource_configuration" "lattice_resource" {
  name            = "agent-tools-resource-config"
  type            = "ARN"
  port_ranges     = ["443"]
  resource_gateway_identifier = var.internal_alb_arn

  resource_configuration_definition {
    arn_resource_configuration_definition {
      arn = var.internal_alb_arn
    }
  }
}

# ==============================================================================
# 2. AWS RAM CROSS-ACCOUNT SHARING TO AGENT ACCOUNT
# ==============================================================================

resource "aws_ram_resource_share" "lattice_ram_share" {
  name                      = "vrm-ai-lattice-tools-share"
  allow_external_principals = true
}

resource "aws_ram_resource_association" "lattice_association" {
  resource_arn       = aws_vpclattice_resource_configuration.lattice_resource.arn
  resource_share_arn = aws_ram_resource_share.lattice_ram_share.arn
}

resource "aws_ram_principal_association" "agent_account_principal" {
  principal          = var.agent_account_id
  resource_share_arn = aws_ram_resource_share.lattice_ram_share.arn
}