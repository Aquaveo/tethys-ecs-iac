# tethys-ecs-iac

Reusable infrastructure-as-code for running a [Tethys Platform](https://www.tethysplatform.org/)
portal on **AWS ECS Fargate** — stateless (external Postgres pooler, S3/CloudFront static+media, no
EFS/Redis), env-neutral, parameterized per org/app.

The IaC is **OpenTofu** — the module, usage, and CI live in [`tofu/`](tofu/). Secrets are **not**
managed by tofu (no secrets in state); create them in SSM with [`put-secrets.sh`](put-secrets.sh).

> This repo previously shipped CloudFormation templates; they were removed once everything moved to
> the OpenTofu module. They remain in git history if you ever need them.

## Quick start
Full details in [`tofu/README.md`](tofu/README.md). In short:

1. **Secrets** — create the SSM SecureStrings under `/<org>/<app>/*`
   (`db-password`, `ps-connection`, `secret-key`, `portal-superuser-password`):
   ```bash
   ORG=<org> APP=<app> ./put-secrets.sh    # e.g. ORG=acme GENKEY=1 AWS_PROFILE=my-sso ./put-secrets.sh
   ```
2. **Deploy** — from `tofu/`, with a per-portal `backend.hcl` (state key) and `<org>.tfvars`:
   ```bash
   cd tofu
   tofu init -backend-config=backend.hcl
   tofu apply -var-file=<org>.tfvars
   ```

## Layout
- `tofu/` — the OpenTofu module (network, roles, cluster, static+CDN, portal task/service) + examples.
- `put-secrets.sh` — one-time SSM SecureString creation per org/app.

Each **portal repo** owns its own `tfvars` / `backend.hcl` / deploy workflow and references this
public module — see [`geoglows/enee-geoglows-portal`](https://github.com/geoglows/enee-geoglows-portal)
for a working example.
