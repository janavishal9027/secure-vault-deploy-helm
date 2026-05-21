#!/usr/bin/env bash
#
# Run from this repo's bitbucket-pipelines.yml (or a developer workstation
# while cd'd into the repo root). Reads per-env config from
# secure-vault-helmchart/envs/<ENV_NAME>/_namespace_values.yaml, syncs the
# deploy repo to the VPS, and invokes ci/deploy-remote.sh inside the LXD
# container.
#
# Required env:
#   ENV_NAME                 Logical env (dev-a / dev-b / test / stage /
#                            prod) — picks the values dir under
#                            secure-vault-helmchart/envs/<ENV_NAME>/.
# Optional (override values from _namespace_values.yaml):
#   VPS_USER, VPS_HOST       SSH login overrides
#   VPS_REMOTE_DIR           Staging dir on the VPS overrides
#   LXD_CONTAINER            Container name override (default = lxd.container)
#   SCOPE                    "all" (default) or comma-separated subset of
#                            service names to roll, e.g. "transaction-service,ui".
#                            Helm renders the full set either way; SCOPE only
#                            narrows which deployments to wait on for rollout.

set -euo pipefail

: "${ENV_NAME:?}"
SCOPE="${SCOPE:-all}"

NS_FILE="secure-vault-helmchart/envs/${ENV_NAME}/_namespace_values.yaml"
[[ -f "$NS_FILE" ]] || { echo "ERROR: $NS_FILE missing" >&2; exit 1; }

read_field() {
  local value
  value=$(yq -r "$1" "$NS_FILE")
  [[ "$value" == "null" ]] && value=""
  echo "$value"
}

VPS_USER="${VPS_USER:-$(read_field '.vps.user')}"
VPS_HOST="${VPS_HOST:-$(read_field '.vps.host')}"
VPS_REMOTE_DIR="${VPS_REMOTE_DIR:-$(read_field '.vps.remoteDir')}"
LXD_CONTAINER="${LXD_CONTAINER:-$(read_field '.lxd.container')}"
LXD_CONTAINER="${LXD_CONTAINER:-secure-vault-$ENV_NAME}"

[[ -n "$VPS_USER"       ]] || { echo "ERROR: vps.user not set in $NS_FILE"       >&2; exit 1; }
[[ -n "$VPS_HOST"       ]] || { echo "ERROR: vps.host not set in $NS_FILE"       >&2; exit 1; }
[[ -n "$VPS_REMOTE_DIR" ]] || { echo "ERROR: vps.remoteDir not set in $NS_FILE"  >&2; exit 1; }

REMOTE_TARGET="${VPS_USER}@${VPS_HOST}"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=10
)

echo "==> Deploying ENV_NAME=${ENV_NAME} LXD_CONTAINER=${LXD_CONTAINER} SCOPE=${SCOPE}"
echo "    Target: ${REMOTE_TARGET}:${VPS_REMOTE_DIR}"

echo "==> Syncing deploy repo to ${VPS_HOST}:${VPS_REMOTE_DIR}"
ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" "mkdir -p '${VPS_REMOTE_DIR}'"
rsync -az --delete --exclude '.git' \
      -e "ssh ${SSH_OPTS[*]}" \
      ./ "${REMOTE_TARGET}:${VPS_REMOTE_DIR}/"

echo "==> Executing deploy-remote.sh on ${VPS_HOST}"
ssh "${SSH_OPTS[@]}" "$REMOTE_TARGET" \
    "env \
      LXD_CONTAINER='${LXD_CONTAINER}' \
      ENV_NAME='${ENV_NAME}' \
      SCOPE='${SCOPE}' \
      REMOTE_DIR='${VPS_REMOTE_DIR}' \
      bash '${VPS_REMOTE_DIR}/ci/deploy-remote.sh'"
