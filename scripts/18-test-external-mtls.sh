#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-bookinfo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Applying STRICT mTLS PeerAuthentication to '${NAMESPACE}'..."
kubectl apply -n "${NAMESPACE}" -f "${SCRIPT_DIR}/../policy/peer-authentication-strict.yaml"

echo "Waiting for policy to take effect..."
sleep 10

echo "Testing external traffic to Ingress Gateway..."
bash "${SCRIPT_DIR}/05-validate.sh"

echo "If the above validation passes, it means external traffic (non-mTLS) is successfully terminated at the Gateway, and internal traffic successfully uses mTLS."
echo "External mTLS test passed!"