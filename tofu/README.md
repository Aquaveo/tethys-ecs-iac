# OpenTofu: Tethys portal on ECS Fargate

OpenTofu equivalent of the CloudFormation templates in the parent directory — one parameterized root
module that stands up a whole portal (network, roles, cluster, static+CDN, task+service) for a new
org/app. Reuse it per portal via a `*.tfvars` file and a per-portal state key.

> Greenfield use (Path A): use this for **new** portals. Existing CloudFormation-managed portals
> (e.g. enee) stay on CloudFormation until you choose to import them.

## What it creates
Everything the CFN stacks did, but cross-stack params (ALB DNS, CloudFront domain) become internal
references — so you don't pass them in:
- `network.tf` — ALB, security groups, target group, HTTP listener
- `roles.tf` — execution role (ECR/logs/SSM) + task role (S3 write)
- `cluster.tf` — ECS cluster + log group
- `static_cdn.tf` — S3 (static/media + geoglows cache lifecycle) + CloudFront (ALB default, S3 for
  `/static` + `/media`) + OAC + bucket policy
- `portal.tf` — task definition (init + web) + Fargate service

## Prerequisites
1. **State bucket** (already created): `tethys-ecs-tofu-state-401506828094` (versioned, encrypted).
2. **Secrets in SSM** under `/<org>/<app>/*` — run `../put-secrets.sh` (db-password, ps-connection,
   secret-key, portal-superuser-password). These are **not** managed by OpenTofu (no secrets in state).
3. **ACM cert** in us-east-1 if you set `portal_domain` (validate it via DNS first).
4. **OpenTofu >= 1.10** (uses native S3 state locking — no DynamoDB).

## Usage
```bash
cp backend.hcl.example backend.hcl                  # set bucket/region/key (key per portal)
cp examples/portal.tfvars.example acme.tfvars       # fill in your values

tofu init -backend-config=backend.hcl
tofu plan  -var-file=acme.tfvars
tofu apply -var-file=acme.tfvars
```
After apply, point your DNS CNAME at the `cloudfront_domain` output, then push the portal image and
re-`apply` with the new `image_uri`/`init_version`.

## State
S3 backend with native locking (`use_lockfile = true`). One **key per portal** (e.g.
`portals/acme-portal.tfstate`) so portals are isolated. `backend.hcl` and real `*.tfvars` are
gitignored; only the `*.example` files are committed.
