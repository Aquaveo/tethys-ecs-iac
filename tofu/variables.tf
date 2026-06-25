variable "region" {
  type    = string
  default = "us-east-1"
}

# ---- naming ----
variable "org" {
  type        = string
  description = "Organization short name (e.g. acme). Combined with app into all resource names."
}
variable "app" {
  type    = string
  default = "portal"
}
variable "environment" {
  type    = string
  default = "production"
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

# ---- network ----
variable "vpc_id" {
  type = string
}
variable "alb_subnets" {
  type        = list(string)
  description = "Public subnets for the ALB (AZs with EFS mount targets if you use EFS)."
}
variable "service_subnets" {
  type        = list(string)
  description = "Subnets to run the Fargate tasks in (public, so they pull from ECR without a NAT)."
}
variable "assign_public_ip" {
  type    = bool
  default = true
}
variable "web_port" {
  type    = number
  default = 8000
}

# ---- roles / secrets ----
variable "ssm_prefix" {
  type        = string
  default     = ""
  description = "SSM SecureString path prefix the exec role may read. Empty -> /<org>/<app>."
}

# ---- static / CDN ----
variable "static_bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket for static + media (and the geoglows cache prefix)."
}
variable "price_class" {
  type    = string
  default = "PriceClass_100"
}
variable "portal_domain" {
  type        = string
  default     = ""
  description = "Public domain (CloudFront alternate domain), e.g. portal.example.org. Empty = *.cloudfront.net only."
}
variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM cert ARN (us-east-1) for portal_domain. Required if portal_domain is set."
}

# ---- cluster ----
variable "log_retention_days" {
  type    = number
  default = 30
}

# ---- portal task ----
variable "image_uri" {
  type        = string
  description = "Full ECR image URI:tag for the portal."
}
variable "task_cpu" {
  type    = string
  default = "1024"
}
variable "task_memory" {
  type    = string
  default = "4096"
}
variable "desired_count" {
  type    = number
  default = 1
}
variable "asgi_processes" {
  type    = string
  default = "2"
}
variable "init_version" {
  type        = string
  description = "run-once guard key (set to the image tag)."
}

# ---- database (Supabase pooler) ----
variable "db_host" {
  type        = string
  description = "Pooler host, e.g. aws-1-us-east-1.pooler.supabase.com"
}
variable "db_username" {
  type        = string
  description = "Pooler username form, e.g. tethys_default.<project_ref>"
}
variable "db_name" {
  type    = string
  default = "tethys_platform"
}
variable "db_port" {
  type    = number
  default = 5432
}
variable "pooler_port" {
  type    = number
  default = 6543
}

# ---- geoglows plot cache (geoglows tethysdash plugin) ----
variable "geoglows_cache_backend" {
  type    = string
  default = "s3"
}
variable "geoglows_cache_prefix" {
  type    = string
  default = "cache/geoglows"
}
