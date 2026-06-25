data "aws_caller_identity" "current" {}

locals {
  name              = "${var.org}-${var.app}"
  ssm_prefix        = var.ssm_prefix != "" ? var.ssm_prefix : "/${var.org}/${var.app}"
  has_custom_domain = var.portal_domain != ""
  account_id        = data.aws_caller_identity.current.account_id

  tags = {
    project = local.name
    env     = var.environment
  }

  # The portal is reached through CloudFront; allow its domain, the ALB DNS, and the public domain.
  # The running task's own private IP is added at startup by portal-config.sh (for the ALB health
  # check), so it is not listed here.
  portal_allowed_hosts = join(",", compact([
    aws_cloudfront_distribution.this.domain_name,
    aws_lb.this.dns_name,
    var.portal_domain,
  ]))
}
