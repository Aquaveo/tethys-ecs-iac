# tethys-ecs-iac

Reusable **OpenTofu** infrastructure-as-code for running a
[Tethys Platform](https://www.tethysplatform.org/) portal on **AWS ECS Fargate** — stateless
(external Postgres pooler, S3/CloudFront static+media, no EFS/Redis), env-neutral, parameterized per
org/app. One root module stands up a whole portal; reuse it per portal via a `*.tfvars` file and a
per-portal state key.

> This repo previously shipped CloudFormation templates; they were removed once everything moved to
> the OpenTofu module under `tofu/`. They remain in git history if you ever need them.

## What it creates (`tofu/`)
Cross-stack values (ALB DNS, CloudFront domain) are internal references — you don't pass them in:
- `network.tf` — ALB, security groups, target group, HTTP listener
- `roles.tf` — execution role (ECR/logs/SSM) + task role (S3 write)
- `cluster.tf` — ECS cluster + log group
- `static_cdn.tf` — S3 (static/media + geoglows cache lifecycle) + CloudFront (ALB default, S3 for
  `/static` + `/media`) + OAC + bucket policy
- `portal.tf` — task definition (init + web) + Fargate service

## Prerequisites
1. **State bucket** (e.g. `tethys-ecs-tofu-state-<account>`): an S3 bucket, versioned + encrypted.
2. **Secrets in SSM** under `/<org>/<app>/*` — run `put-secrets.sh` (db-password, ps-connection,
   secret-key, portal-superuser-password). These are **not** managed by OpenTofu (no secrets in state).
3. **ACM cert** in us-east-1 if you set `portal_domain` (validate it via DNS first).
4. **OpenTofu >= 1.10** (uses native S3 state locking — no DynamoDB).

## Usage
```bash
# 1. secrets (one-time per org/app)
ORG=<org> APP=<app> ./put-secrets.sh        # e.g. ORG=acme GENKEY=1 AWS_PROFILE=my-sso ./put-secrets.sh

# 2. deploy
cd tofu
cp backend.hcl.example backend.hcl          # set bucket/region + a per-portal key
cp examples/portal.tfvars.example acme.tfvars
tofu init -backend-config=backend.hcl
tofu plan  -var-file=acme.tfvars
tofu apply -var-file=acme.tfvars
```
After apply, point your DNS CNAME at the `cloudfront_domain` output, then push the portal image and
re-`apply` with the new `image_uri`/`init_version`.

### Local credentials (SSO gotcha)
OpenTofu's AWS provider (Go SDK) does **not** auto-refresh AWS SSO tokens the way the AWS CLI does —
running `tofu` against an SSO profile can fail with `ExpiredToken` even when `aws ... --profile` works.
Hand tofu fresh credentials derived from the (refreshed) CLI profile:
```bash
aws sso login --sso-session <your-sso-session>
eval "$(aws configure export-credentials --profile <your-sso-profile> --format env)"
tofu plan -var-file=acme.tfvars
```
(In CI this is a non-issue — OIDC provides credentials directly as env vars.)

## State
S3 backend with native locking (`use_lockfile = true`). One **key per portal** (e.g.
`portals/acme-portal.tfstate`) so portals are isolated. `backend.hcl` and real `*.tfvars` are
gitignored; only the `*.example` files are committed here.

## Deploy / CI ownership
This repo stays **general** — it holds only the module + examples. Each **portal repo** owns its own
specifics (its `*.tfvars`, `backend.hcl`, the GitHub OIDC deploy role, and the deploy workflow). A
portal's deploy workflow checks out this repo's `tofu/` (it's public), then runs
`tofu init -backend-config=<its backend.hcl>` + `tofu apply -var-file=<its tfvars>` against its own
state key. See [`geoglows/enee-geoglows-portal`](https://github.com/geoglows/enee-geoglows-portal)
for a working example.
