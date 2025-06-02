output "firewall_id" {
  description = "ID of the Network Firewall"
  value       = aws_networkfirewall_firewall.main.id
}

output "firewall_arn" {
  description = "ARN of the Network Firewall"
  value       = aws_networkfirewall_firewall.main.arn
}

output "firewall_status" {
  description = "Status of the firewall"
  value       = aws_networkfirewall_firewall.main.firewall_status
}

output "firewall_policy_id" {
  description = "ID of the Network Firewall Policy"
  value       = aws_networkfirewall_firewall_policy.main.id
}

output "custom_http_rule_group_arn" {
  description = "ARN of the custom HTTP headers rule group"
  value       = aws_networkfirewall_rule_group.custom_http_headers.arn
}

output "flow_log_group" {
  description = "CloudWatch Log Group for Network Firewall flow logs"
  value       = aws_cloudwatch_log_group.network_firewall_flow.name
}

output "alert_log_group" {
  description = "CloudWatch Log Group for Network Firewall alert logs"
  value       = aws_cloudwatch_log_group.network_firewall_alert.name
}

output "tls_log_group" {
  description = "CloudWatch Log Group for Network Firewall TLS logs"
  value       = aws_cloudwatch_log_group.network_firewall_tls.name
}

output "firewall_endpoints_by_az" {
  description = "Map of AZ to Network Firewall endpoint IDs"
  value       = local.firewall_endpoints_by_az
} 