# aws/cloudformation

CloudFormation templates to run a Tethys portal on AWS ECS **Fargate**, reusable across
organizations. All resource names derive from two parameters - `Org` and `App` - so every org gets
its own `${Org}-${App}-*` stack with no shared/hardcoded names. Account-specific values (VPC, subnets,
EFS id, bucket names) are template parameters supplied via per-org files; secrets live in SSM.

## Prerequisites

- An AWS account with an existing VPC, public subnets, and an EFS file system.
- AWS credentials configured. Export your profile/region once so every command below picks them up:
  ```bash
  export AWS_PROFILE=<your-profile>    # or use default credentials / an SSO session
  export AWS_REGION=<your-region>      # e.g. us-east-1
  # if using SSO:  aws sso login --sso-session <your-sso-session>
  ```

## Conventions

- **Naming:** `Org` (e.g. `acme`) + `App` (default `portal`) → resources named `${Org}-${App}-*`,
  Cloud Map namespace from `PrivateNamespace`, SSM secrets under `/<Org>/<App>/*`.
- **Per-org parameter files:** each template reads its inputs from a JSON file in `parameters/`.
  Committed `*.example.json` files hold placeholders; copy each to a real file (which is gitignored)
  and fill in your values:
  ```bash
  cd parameters
  for s in static-cdn network roles cluster; do cp $s.example.json $s.json; done
  # then edit *.json with your Org, VPC, subnets, EFS id, bucket name, namespace, SSM prefix
  ```
- Deploy each stack with `--parameter-overrides file://<file>`.

## 1. `static-cdn.yaml` - static files bucket + CloudFront

Private S3 bucket (Block Public Access on) + CloudFront with Origin Access Control. django-storages
uploads collected static to the bucket; the portal serves it via the CloudFront domain.

```bash
aws cloudformation deploy \
  --template-file static-cdn.yaml \
  --stack-name <org>-<app>-static \
  --parameter-overrides file://parameters/static-cdn.json
```
Read the outputs and set them in the portal env (`.env` / SSM):
```bash
aws cloudformation describe-stacks --stack-name <org>-<app>-static \
  --query 'Stacks[0].Outputs' --output table
# -> STATIC_S3_BUCKET=<BucketName>,  STATIC_CLOUDFRONT_DOMAIN=<CloudFrontDomain>
```
Notes:
- `BucketName` must be globally unique; if it's taken, pick another and set `STATIC_S3_BUCKET` to match.
- CloudFront takes a few minutes; the domain works once the stack completes.
- The task role (step 2) grants S3 **write** to this bucket for `publish-static.sh`'s collectstatic upload.

## 2. ECS stack (Fargate)

Launch type **Fargate**, fully parallel to any existing deployment. Names are env-neutral (`Org`/`App`)
so the same stack validates as a staging candidate and is **promoted in place to production** once
blessed - no rename, no new ALB DNS. (Production cutover adds HTTPS:443 + an ACM cert + your DNS to
`ecs-network.yaml`, and ≥2 web tasks on FARGATE on-demand.)

Deploy in order (each a separate `aws cloudformation deploy`):

```bash
aws cloudformation deploy --template-file ecs-network.yaml \
  --stack-name <org>-<app>-network --parameter-overrides file://parameters/network.json

aws cloudformation deploy --template-file ecs-roles.yaml \
  --stack-name <org>-<app>-roles --parameter-overrides file://parameters/roles.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation deploy --template-file ecs-cluster.yaml \
  --stack-name <org>-<app>-cluster --parameter-overrides file://parameters/cluster.json

aws cloudformation deploy --template-file ecs-portal.yaml \
  --stack-name <org>-<app>-web --parameter-overrides file://parameters/portal.json \
  --capabilities CAPABILITY_NAMED_IAM
```

1. `ecs-network.yaml` - security groups (ALB, web-task) + the portal ALB + listener. Reuses your
   existing VPC/subnets.
2. `ecs-roles.yaml` - execution role (ECR pull, SSM read on `/<Org>/<App>/*`, CloudWatch logs) + task
   role (**S3 write** to the static bucket). Needs `CAPABILITY_NAMED_IAM`.
3. `ecs-cluster.yaml` - the Fargate cluster (`${Org}-${App}`) + CloudWatch log group.
4. `ecs-portal.yaml` - stateless portal task def (init `essential:false` + web + valkey) + service +
   ALB target group/listener. Secrets from SSM, env wired to the database + static. No EFS.

## 3. Secrets - create the SSM params (required before `ecs-portal.yaml`)

The portal's sensitive values are stored as **SSM SecureString** params under `/<Org>/<App>/*` (KMS-
encrypted) and injected into the task at runtime via the task def `secrets:` block - never baked into
the image, repo, or template. The exec role from step 2 already has `ssm:GetParameters` on this path
+ `kms:Decrypt`.

Create them with the helper (hidden input - values never hit screen/history/repo):
```bash
ORG=<org> bash put-secrets.sh              # prompts for each value
ORG=<org> GENKEY=1 bash put-secrets.sh     # also auto-generates a fresh Django SECRET_KEY
```
> If any of these values were ever exposed (committed, pasted, logged), rotate them at the source
> (database / dashboard) **before** storing them here, and treat the old values as compromised.

Params created (suffix → env var the task def maps it to):

| `/<Org>/<App>/...` | env var | value |
|---|---|---|
| `db-password` | `TETHYS_DB_PASSWORD` | database app-role password |
| `ps-connection` | `TETHYS_PS_CONNECTION` | session-pooler conn string `:5432` (embeds pw) |
| `secret-key` | `TETHYS_SECRET_KEY` | Django secret key |
| `portal-superuser-password` | `PORTAL_SUPERUSER_PASSWORD` | portal admin login |

Non-secret config (pooler host/port, service name, static bucket/CloudFront, `INIT_VERSION`) goes in
the task def as **plain `environment:`**, not here. Verify:
```bash
aws ssm get-parameters-by-path --path /<org>/<app> --recursive \
  --query 'Parameters[].Name' --output table
```

## 4. Push the portal image to ECR (required before `ecs-portal.yaml`)

The Fargate task pulls the portal image from an ECR repo. **The tag is significant**: it doubles as the
portal's `INIT_VERSION` and the S3 static-files prefix (`STATIC_S3_BUCKET/<tag>/...`), so the running
task, the collected static, and the CloudFront path all line up. Use the same value everywhere.

```bash
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REG="${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com/<ecr-repo>"
TAG=<tag>          # = INIT_VERSION = static prefix, e.g. v2026-06-23

# create the repo once if it doesn't exist:
aws ecr describe-repositories --repository-names <ecr-repo> >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name <ecr-repo> >/dev/null

# log Docker in, build, tag, push
aws ecr get-login-password | docker login --username AWS --password-stdin "${REG%/*}"
docker build -t "$REG:$TAG" .          # from the repo root
docker push "$REG:$TAG"
```
Then wire the **same tag** into the portal task def / env:
- `ecs-portal.yaml` container `Image: <account>.dkr.ecr.<region>.amazonaws.com/<ecr-repo>:<tag>`
- `INIT_VERSION=<tag>` (run-once markers + collectstatic version)
- static prefix = `<tag>` (django-storages `location`; CloudFront serves `https://<domain>/<tag>/...`)

Confirm a tag landed:
```bash
aws ecr describe-images --repository-name <ecr-repo> \
  --query 'reverse(sort_by(imageDetails,&imagePushedAt))[:5].imageTags' --output table
```
