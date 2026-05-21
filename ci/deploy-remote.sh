#!/usr/bin/env bash
#
# Runs ON THE LXD HOST. Resolves the per-env values files + image-versions
# file and runs `helm upgrade --install` inside the LXD container.
#
# Required env (passed in by ci/deploy.sh):
#   LXD_CONTAINER, ENV_NAME, REMOTE_DIR
# Optional:
#   SCOPE   "all" or comma-separated subset of service names. Default "all".
#
# Layout assumed (relative to $REMOTE_DIR):
#   secure-vault-helmchart/                 chart sources
#   secure-vault-helmchart/envs/<ENV>/      _namespace_values.yaml + per-svc files
#   image-versions/<ENV>_image.yaml         image tag map (loaded last)

set -euxo pipefail

: "${LXD_CONTAINER:?}"
: "${ENV_NAME:?}"
: "${REMOTE_DIR:?}"
SCOPE="${SCOPE:-all}"

export PATH="/snap/bin:$PATH"

LOG_DIR="${REMOTE_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${ENV_NAME}-$(date -Iseconds).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== deploy-remote.sh starting at $(date -Iseconds) ==="
echo "    LXD_CONTAINER=$LXD_CONTAINER  ENV_NAME=$ENV_NAME  SCOPE=$SCOPE"

cd "$REMOTE_DIR"

CHART_DIR="secure-vault-helmchart"
ENV_DIR="${CHART_DIR}/envs/${ENV_NAME}"
IMAGE_FILE="image-versions/${ENV_NAME}_image.yaml"

[[ -d "$CHART_DIR" ]]         || { echo "ERROR: chart dir missing: $CHART_DIR" >&2; exit 1; }
[[ -d "$ENV_DIR" ]]           || { echo "ERROR: env dir missing: $ENV_DIR" >&2; exit 1; }
[[ -f "$IMAGE_FILE" ]]        || { echo "ERROR: image-versions file missing: $IMAGE_FILE" >&2; exit 1; }
[[ -f "$ENV_DIR/_namespace_values.yaml" ]] || \
  { echo "ERROR: $ENV_DIR/_namespace_values.yaml missing — set namespace + ingressHost there" >&2; exit 1; }

CONTAINER_DIR="/tmp/secure-vault-deploy"
lxc exec "$LXD_CONTAINER" -- rm -rf "$CONTAINER_DIR"
lxc exec "$LXD_CONTAINER" -- mkdir -p "$CONTAINER_DIR"
tar -cf - "$CHART_DIR" "$IMAGE_FILE" | lxc exec "$LXD_CONTAINER" -- tar -xf - -C "$CONTAINER_DIR"

echo "=== Waiting for k3s in $LXD_CONTAINER ==="
for i in $(seq 1 60); do
  if lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl get nodes >/dev/null 2>&1; then
    break
  fi
  echo "  attempt $i/60: k3s API not yet responding, retrying in 5s..."
  sleep 5
done
lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl get nodes >/dev/null

NAMESPACE=$(grep -E '^namespace:' "$ENV_DIR/_namespace_values.yaml" | awk '{print $2}' | tr -d '"')
[[ -n "$NAMESPACE" ]] || { echo "ERROR: could not parse namespace from _namespace_values.yaml" >&2; exit 1; }
echo "=== Namespace: $NAMESPACE ==="

lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
  || lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl create namespace "$NAMESPACE"

HELM_ARGS=(-f "${CONTAINER_DIR}/${ENV_DIR}/_namespace_values.yaml")
for f in "$ENV_DIR"/*_values.yaml; do
  [[ "$(basename "$f")" == "_namespace_values.yaml" ]] && continue
  HELM_ARGS+=(-f "${CONTAINER_DIR}/${f}")
done
HELM_ARGS+=(-f "${CONTAINER_DIR}/${IMAGE_FILE}")

if [[ "$SCOPE" == "all" ]]; then
  WAIT_SVCS=()
  for f in "$ENV_DIR"/*_values.yaml; do
    [[ "$(basename "$f")" == "_namespace_values.yaml" ]] && continue
    svc=$(basename "$f" _values.yaml)
    WAIT_SVCS+=("$svc")
  done
else
  IFS=',' read -ra WAIT_SVCS <<< "$SCOPE"
  for svc in "${WAIT_SVCS[@]}"; do
    [[ -f "$ENV_DIR/${svc}_values.yaml" ]] || \
      { echo "ERROR: requested service '$svc' has no values file" >&2; exit 1; }
  done
fi

echo "=== helm upgrade --install (release: secure-vault, namespace: $NAMESPACE) ==="
echo "    args: ${HELM_ARGS[*]}"

lxc exec "$LXD_CONTAINER" -- helm upgrade --install secure-vault \
  "${CONTAINER_DIR}/${CHART_DIR}" \
  -n "$NAMESPACE" --create-namespace \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  "${HELM_ARGS[@]}"

echo "=== Waiting for rollouts to be Available (services: ${WAIT_SVCS[*]}) ==="
for svc in "${WAIT_SVCS[@]}"; do
  echo "--- waiting for ${svc}-deployment ---"
  lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl -n "$NAMESPACE" \
    rollout status "deployment/${svc}-deployment" --timeout=240s || {
    echo "ERROR: ${svc}-deployment did not become Available within 240s" >&2
    lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl -n "$NAMESPACE" \
      describe "deployment/${svc}-deployment" >&2 || true
    lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl -n "$NAMESPACE" \
      logs -l "app=${svc}" --tail=80 >&2 || true
    exit 1
  }
done

echo "=== Final namespace state ==="
lxc exec "$LXD_CONTAINER" -- /usr/local/bin/k3s kubectl -n "$NAMESPACE" \
  get all,ingress -o wide
echo "=== Deploy complete: $ENV_NAME @ $LXD_CONTAINER  scope=$SCOPE ==="
echo "=== deploy-remote.sh finished at $(date -Iseconds) ==="
