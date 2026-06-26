# TEMPLATE — copy into a portal repo as tofu-iam/ and edit the variable defaults below.
#
# GitHub OIDC -> AWS CI roles (ECR push + tofu deploy). Bootstrap config: apply ONCE with ADMIN
# credentials (it creates the role the deploy CI assumes, so the deploy CI cannot create it). Keep
# its state separate from the portal infra (its own key). No CloudFormation.
#
#   eval "$(aws configure export-credentials --profile <admin-sso> --format env)"
#   cd tofu-iam
#   tofu init -backend-config=backend.hcl     # key e.g. portals/<org>-portal-iam.tfstate
#   tofu apply

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}
variable "github_org" {
  type    = string
  default = "<github-org>" # <-- EDIT
}
variable "github_repo" {
  type    = string
  default = "<portal-repo>" # <-- EDIT
}
variable "ecr_repository" {
  type    = string
  default = "tethys-portal" # <-- EDIT if different
}
variable "state_bucket" {
  type    = string
  default = "<tofu-state-bucket>" # <-- EDIT
}
# Set true only if the account does NOT already have the GitHub OIDC provider.
variable "create_oidc_provider" {
  type    = bool
  default = false
}

data "aws_caller_identity" "me" {}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  account = data.aws_caller_identity.me.account_id
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (
    "arn:aws:iam::${local.account}:oidc-provider/token.actions.githubusercontent.com"
  )
}

# Trust: only this repo's workflows may assume these roles via OIDC.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

# ---- ECR push role (build workflow) ----
resource "aws_iam_role" "ecr" {
  name               = "${var.github_repo}-ci-ecr"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
    ]
    resources = ["arn:aws:ecr:${var.region}:${local.account}:repository/${var.ecr_repository}"]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ecr.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# ---- tofu deploy role (tofu-deploy + sync-secrets workflows). Powerful; tighten if desired. ----
resource "aws_iam_role" "deploy" {
  name               = "${var.github_repo}-tofu-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "deploy_poweruser" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "deploy_iam" {
  statement {
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:PassRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:ListRolePolicies", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${local.account}:role/*"]
  }
}

resource "aws_iam_role_policy" "deploy_iam" {
  name   = "iam-role-management"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_iam.json
}

data "aws_iam_policy_document" "deploy_state" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "deploy_state" {
  name   = "tofu-state"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_state.json
}

output "ecr_role_arn" {
  description = "Set as the GitHub repo secret AWS_ROLE_ARN."
  value       = aws_iam_role.ecr.arn
}
output "deploy_role_arn" {
  description = "Set as the GitHub repo secret AWS_DEPLOY_ROLE_ARN."
  value       = aws_iam_role.deploy.arn
}
