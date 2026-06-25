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
`portals/acme-portal.tfstate`) so portals are isolated. A loose root `backend.hcl` / `*.tfvars` are
gitignored; per-portal configs under `portals/<org>/` **are** committed (see CI below).

## Deploy via CI (push-button)
A `workflow_dispatch` workflow (`.github/workflows/tofu-deploy.yml`) runs `tofu plan`/`apply` for a
portal whose config lives at `tofu/portals/<org>/{backend.hcl, <org>.tfvars}` (see
`tofu/portals/example/`). Auth is GitHub OIDC — no stored AWS keys.

1. Create the deploy role once (it's powerful — PowerUser + IAM role management; tighten if desired):
   ```bash
   aws cloudformation deploy --template-file deploy/github-oidc-tofu.yaml \
     --stack-name tethys-ecs-iac-tofu-deploy --capabilities CAPABILITY_NAMED_IAM \
     --region us-east-1 --profile <admin>
   ```
2. Set repo **secret** `AWS_DEPLOY_ROLE_ARN` (the stack's `RoleArn` output) and **var** `AWS_REGION`.
3. Add `tofu/portals/<org>/` (copy from `example/`), commit, then run the **tofu deploy** workflow
   with `portal=<org>` and `action=plan` (review), then `action=apply`.

> Prefer the deploy workflow to live in each portal repo instead of here? Change its trigger to
> `workflow_call` and invoke it from the portal repo (which then supplies its own tfvars/backend).
