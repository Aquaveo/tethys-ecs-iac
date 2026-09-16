# Security groups
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "${local.name} ALB (public HTTP)"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-alb" })
}

# With the ALB open to the world on 80, the portal is reachable in plaintext at the load balancer
# DNS name, which bypasses the distribution and its redirect-to-https entirely. Restricting ingress
# to CloudFront's origin-facing ranges closes that path and is what makes edge_proto_header
# trustworthy: a custom header is not overwritten by the ALB, so it can only be believed when
# nothing but CloudFront can reach the listener.
data "aws_ec2_managed_prefix_list" "cloudfront_origins" {
  count = var.restrict_alb_to_cloudfront ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count             = var.restrict_alb_to_cloudfront ? 0 : 1
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_cloudfront" {
  count             = var.restrict_alb_to_cloudfront ? 1 : 0
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront origin-facing ranges only"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origins[0].id
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "web" {
  name        = "${local.name}-web"
  description = "${local.name} web task"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-web" })
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web.id
  description                  = "uvicorn from the ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.web_port
  to_port                      = var.web_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ALB + target group + listener
resource "aws_lb" "this" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.alb_subnets
  security_groups    = [aws_security_group.alb.id]
  tags               = local.tags
}

resource "aws_lb_target_group" "portal" {
  name                 = "${local.name}-tg"
  vpc_id               = var.vpc_id
  target_type          = "ip" # Fargate (awsvpc) registers task IPs
  port                 = var.web_port
  protocol             = "HTTP"
  deregistration_delay = 30

  health_check {
    protocol          = "HTTP"
    path              = "/"
    matcher           = "200-399"
    interval          = 30
    healthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portal.arn
  }
}
