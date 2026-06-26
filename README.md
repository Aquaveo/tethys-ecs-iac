# tethys-ecs-iac

Reusable **OpenTofu** infrastructure-as-code for running a
[Tethys Platform](https://www.tethysplatform.org/) portal on **AWS ECS Fargate** — stateless
(external Postgres pooler, S3/CloudFront static+media, no EFS/Redis), env-neutral, parameterized per
org/app. One root module stands up a whole portal; reuse it per portal via a `*.tfvars` file and a
per-portal state key.

> This repo previously shipped CloudFormation templates + a `put-secrets.sh` helper; both were removed
> once everything moved to the OpenTofu module (`tofu/`) and CI-driven secrets. They remain in git
> history if you ever need them.

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
2. **Secrets in SSM** under `/<org>/<app>/*` — see [Secrets](#secrets) below. **Not** managed by
   OpenTofu (no secrets in state).
3. **ACM cert** in us-east-1 if you set `portal_domain` (validate it via DNS first).
4. **OpenTofu >= 1.10** (uses native S3 state locking — no DynamoDB).

## Usage
```bash
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

## Secrets
Secrets are kept **out of tofu state** and **out of the image**. The flow is:

```
GitHub Secrets  ──(sync-secrets CI, OIDC)──>  SSM SecureStrings /<org>/<app>/*  ──>  ECS task (runtime)
```

Four parameters back the portal:

| GitHub Secret | SSM param `/<org>/<app>/…` | Injected as | Purpose |
|---|---|---|---|
| `DB_PASSWORD` | `db-password` | `TETHYS_DB_PASSWORD` | database (Postgres pooler) password |
| `PS_CONNECTION` | `ps-connection` | `TETHYS_PS_CONNECTION` | persistent-store connection string |
| `SECRET_KEY` | `secret-key` | `TETHYS_SECRET_KEY` | Django `SECRET_KEY` (cookie/CSRF/token signing) |
| `SUPERUSER_PASSWORD` | `portal-superuser-password` | `PORTAL_SUPERUSER_PASSWORD` | portal `admin` UI / Django-admin login |

Set them as GitHub Secrets in the portal repo and run the **sync-secrets** workflow (template:
[`examples/portal-ci/sync-secrets.yml`](examples/portal-ci/sync-secrets.yml)) — it writes them to SSM
via OIDC. The ECS task reads them from SSM at runtime. Rotate by updating the GitHub Secret and
re-running the workflow.

> Notes: rotating `SECRET_KEY` logs everyone out (invalidates sessions + signed tokens). The
> superuser is named `admin` (`PORTAL_SUPERUSER_NAME`) and is applied by the init container at boot.

## State
S3 backend with native locking (`use_lockfile = true`). One **key per portal** (e.g.
`portals/acme-portal.tfstate`) so portals are isolated. `backend.hcl` and real `*.tfvars` are
gitignored; only the `*.example` files are committed here.

## Per-portal CI (templates)
This repo stays **general** — it holds only the module + examples. Each **portal repo** owns its own
`*.tfvars`, `backend.hcl`, and CI. Copy the kit in [`examples/portal-ci/`](examples/portal-ci/) into a
new portal repo and fill in the placeholders:

| Template | Goes to | Purpose |
|---|---|---|
| `tofu-iam/` | `tofu-iam/` (apply once, admin creds) | OpenTofu for the OIDC CI roles (ECR push + tofu deploy) — no CloudFormation |
| `tofu-deploy.yml` | `.github/workflows/` | `plan`/`apply` infra (checks out this module, uses the portal's tfvars/backend) |
| `sync-secrets.yml` | `.github/workflows/` | push the portal's GitHub Secrets to SSM |

Repo settings each portal sets: secret `AWS_DEPLOY_ROLE_ARN` (role output), var `AWS_REGION`, plus the
secret values. See [`geoglows/enee-geoglows-portal`](https://github.com/geoglows/enee-geoglows-portal)
for a working example.
