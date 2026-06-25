terraform {
  # S3 remote state with native S3 locking (OpenTofu >= 1.10, no DynamoDB needed).
  # Partial config: supply bucket/key/region per portal at init, e.g.
  #   tofu init -backend-config=backend.hcl
  # where backend.hcl sets bucket, region, and a per-portal key (key = "portals/<org>-<app>.tfstate").
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
