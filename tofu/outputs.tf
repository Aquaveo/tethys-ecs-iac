output "alb_dns_name" {
  description = "ALB DNS name (the CloudFront default origin)."
  value       = aws_lb.this.dns_name
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain (point your DNS CNAME here)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "static_bucket" {
  value = aws_s3_bucket.static.id
}

output "ecs_cluster" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.portal.name
}

output "portal_allowed_hosts" {
  description = "Computed ALLOWED_HOSTS passed to the task (CloudFront + ALB + domain)."
  value       = local.portal_allowed_hosts
}

# --- consumed by the CI provision-then-roll step ---
output "web_task_definition" {
  description = "Latest web task def ARN; CI points the service here after provisioning succeeds."
  value       = aws_ecs_task_definition.portal.arn
}

output "provision_task_definition" {
  description = "One-shot provision task def ARN; CI run-tasks this before rolling the service."
  value       = aws_ecs_task_definition.provision.arn
}

output "provision_container_name" {
  value = "provision"
}

output "service_subnets" {
  value = var.service_subnets
}

output "web_security_group" {
  value = aws_security_group.web.id
}

output "assign_public_ip" {
  value = var.assign_public_ip
}
