# Per-portal config consumed by the tofu-deploy workflow (input: portal=example).
# Copy this dir to tofu/portals/<org>/ and rename the tfvars to <org>.tfvars.
# Values here are account IDs/ARNs, not secrets (passwords stay in SSM).
org         = "example"
app         = "portal"
environment = "production"
region      = "us-east-1"

vpc_id          = "vpc-xxxxxxxx"
alb_subnets     = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]
service_subnets = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]

static_bucket_name  = "example-portal-static"
portal_domain       = "portal.example.org"
acm_certificate_arn = "arn:aws:acm:us-east-1:000000000000:certificate/xxxxxxxx"

image_uri    = "000000000000.dkr.ecr.us-east-1.amazonaws.com/tethys-portal:<tag>"
init_version = "<tag>"
task_cpu     = "1024"
task_memory  = "4096"
desired_count = 1

db_host     = "aws-1-us-east-1.pooler.supabase.com"
db_username = "tethys_default.<project_ref>"
db_name     = "tethys_platform"
db_port     = 5432
pooler_port = 6543
