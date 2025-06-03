# Get current AWS region
data "aws_region" "current" {}

# AWS Network Firewall Policy
resource "aws_networkfirewall_firewall_policy" "main" {
  name = "${var.project_name}-${var.environment}-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    # only available from terraform provider 5.x
    policy_variables {
      rule_variables {
        key = "HOME_NET"
        ip_set {
          definition = var.public_subnet_cidrs
        }
      }
    }

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.custom_http_headers.arn
      priority     = 5
    }

    stateful_rule_group_reference {
      resource_arn = "arn:aws:network-firewall:${data.aws_region.current.name}:aws-managed:stateful-rulegroup/ThreatSignaturesScannersStrictOrder"
      priority     = 10
    }

    # Add TLS inspection configuration if certificate is provided
    tls_inspection_configuration_arn = aws_networkfirewall_tls_inspection_configuration.main_tls.arn
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-firewall-policy"
  }
}

# Custom rule group for HTTP header inspection
resource "aws_networkfirewall_rule_group" "custom_http_headers" {
  capacity = 100
  name     = "${var.project_name}-${var.environment}-http-headers"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_string = <<EOF
# Block HTTP requests with 'attack' header
drop http any any -> $HOME_NET any (msg:"Attack header detected"; flow:established,to_server; http.header; content:"attack"; nocase; sid:1000001; rev:1;)

# Additional HTTP header inspection rules
drop http any any -> $HOME_NET any (msg:"Malicious header detected - XSS attempt"; flow:established,to_server; http.header; content:"<script>"; nocase; sid:1000002; rev:1;)

# Block requests with specific query parameters
drop http any any -> $HOME_NET any (msg:"SQL Injection attempt in query"; flow:established,to_server; http.uri; content:"union"; nocase; content:"select"; nocase; sid:1000003; rev:1;)
EOF
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-http-headers"
  }
}

# AWS Network Firewall
resource "aws_networkfirewall_firewall" "main" {
  name                = "${var.project_name}-${var.environment}-network-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = var.vpc_id

  delete_protection = false

  # Deploy Network Firewall in public subnets to inspect traffic from Internet Gateway
  dynamic "subnet_mapping" {
    for_each = var.firewall_subnet_ids
    content {
      subnet_id = subnet_mapping.value
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-network-firewall"
  }
}

# CloudWatch Log Groups for Network Firewall logs
resource "aws_cloudwatch_log_group" "network_firewall_flow" {
  name              = "/aws/network-firewall/${var.project_name}-${var.environment}/flow"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-network-firewall-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "network_firewall_alert" {
  name              = "/aws/network-firewall/${var.project_name}-${var.environment}/alert"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-network-firewall-alert-logs"
  }
}

resource "aws_cloudwatch_log_group" "network_firewall_tls" {
  name              = "/aws/network-firewall/${var.project_name}-${var.environment}/tls"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-network-firewall-tls-logs"
  }
}

# Configure Network Firewall logging
resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall_flow.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall_alert.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall_tls.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "TLS"
    }
  }
}
resource "aws_networkfirewall_tls_inspection_configuration" "main_tls" {
  name        = "${var.project_name}-${var.environment}-tls-inspection"
  description = "${var.project_name}-${var.environment}-tls-inspection"

  tls_inspection_configuration {
    server_certificate_configuration {
      server_certificate {
        resource_arn = var.alb_certificate_arn
      }
      scope {
        protocols = [6]
        destination_ports {
          from_port = 443
          to_port   = 443
        }
        dynamic "destination" {
          for_each = var.public_subnet_cidrs
          content {
            address_definition = destination.value
          }
        }
        source_ports {
          from_port = 0
          to_port   = 65535
        }
        source {
          address_definition = "0.0.0.0/0"
        }
      }
    }
  }
}
