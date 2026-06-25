#!/usr/bin/env bash
# Create/update the portal's SSM SecureString secrets under /<ORG>/<APP>/*.
#
# Values are read with hidden input (read -s), so they never appear on screen, in shell history,
# or in this repo. Re-runnable (--overwrite). The exec role created by ecs-roles.yaml already has
# ssm:GetParameters on this prefix + kms:Decrypt, so the ECS task def references these via `secrets:`.
#
# Config (env vars):
#   ORG          required   organization short name (e.g. acme)        -> prefix /<ORG>/<APP>
#   APP          default portal
#   AWS_REGION   default us-east-1
#   AWS_PROFILE  optional   passed as --profile if set; else default credentials are used
#   GENKEY=1     optional   auto-generate a fresh Django SECRET_KEY instead of prompting
#
# Usage:
#   ORG=acme bash aws/cloudformation/put-secrets.sh
#   ORG=acme GENKEY=1 AWS_PROFILE=my-sso bash aws/cloudformation/put-secrets.sh
set -euo pipefail

: "${ORG:?set ORG=<org short name>, e.g. ORG=acme}"
APP="${APP:-portal}"
REGION="${AWS_REGION:-us-east-1}"
PREFIX="/${ORG}/${APP}"

AWS_ARGS=(--region "${REGION}")
[[ -n "${AWS_PROFILE:-}" ]] && AWS_ARGS+=(--profile "${AWS_PROFILE}")

put () {  # put <param-suffix> <prompt> -- prompts hidden, writes SecureString
  local suffix="$1" prompt="$2" name="${PREFIX}/$1" val
  read -rsp "  ${prompt}: " val; echo
  if [[ -z "${val}" ]]; then echo "  (skipped ${name} -- empty)"; return; fi
  aws ssm put-parameter --name "${name}" --type SecureString --value "${val}" \
    --overwrite "${AWS_ARGS[@]}" >/dev/null
  echo "  ✓ ${name}"
}

echo "Writing SecureString params to ${PREFIX}/* in ${REGION}${AWS_PROFILE:+ (profile ${AWS_PROFILE})}"
echo "Press Enter on an empty value to skip that one."
echo

# --- Database ------------------------------------------------------------------------------------
put db-password               "Database app-role password                (env TETHYS_DB_PASSWORD)"
put ps-connection             "Session-pooler conn string :5432, embeds pw (env TETHYS_PS_CONNECTION)"

# --- Django / portal -----------------------------------------------------------------------------
if [[ "${GENKEY:-}" == "1" ]]; then
  key="$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')"
  aws ssm put-parameter --name "${PREFIX}/secret-key" --type SecureString --value "${key}" \
    --overwrite "${AWS_ARGS[@]}" >/dev/null
  echo "  ✓ ${PREFIX}/secret-key  (auto-generated)"
else
  put secret-key              "Django SECRET_KEY                         (env TETHYS_SECRET_KEY)"
fi
put portal-superuser-password "Portal admin (Tethys) password            (env PORTAL_SUPERUSER_PASSWORD)"

echo
echo "Done. Verify (names + last-modified only, values stay encrypted):"
echo "  aws ssm get-parameters-by-path --path ${PREFIX} --recursive \\"
echo "    --query 'Parameters[].Name' --region ${REGION}${AWS_PROFILE:+ --profile ${AWS_PROFILE}} --output table"
