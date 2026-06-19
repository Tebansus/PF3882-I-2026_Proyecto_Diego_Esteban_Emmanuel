#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-bookinfo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_DIR="${SCRIPT_DIR}/../platform/kube"

echo "Deploying sleep pod in 'default' namespace (no Istio sidecar)..."
kubectl apply -n default -f "${SCRIPT_DIR}/samples/sleep.yaml"

echo "Deploying sleep pod in '${NAMESPACE}' namespace (with Istio sidecar)..."
kubectl apply -n "${NAMESPACE}" -f "${SCRIPT_DIR}/samples/sleep.yaml"

echo "Waiting for sleep pods to be ready..."
kubectl wait --for=condition=ready pod -l app=sleep -n default --timeout=60s
kubectl wait --for=condition=ready pod -l app=sleep -n "${NAMESPACE}" --timeout=60s

echo "Applying STRICT mTLS PeerAuthentication to '${NAMESPACE}'..."
kubectl apply -n "${NAMESPACE}" -f "${SCRIPT_DIR}/../policy/peer-authentication-strict.yaml"

echo "Waiting for policy to take effect..."
sleep 10

echo "Testing from 'default' namespace (should fail due to STRICT mTLS)..."
if kubectl exec "$(kubectl get pod -l app=sleep -n default -o jsonpath={.items..metadata.name})" -n default -c sleep -- curl -s http://productpage.${NAMESPACE}.svc.cluster.local:9080/productpage | grep -qi "Simple Bookstore App"; then
  echo "ERROR: Request from default namespace succeeded, but it should have failed!"
  exit 1
else
  echo "SUCCESS: Request from default namespace failed as expected."
fi

echo "Testing from '${NAMESPACE}' namespace (should succeed with mTLS)..."
if kubectl exec "$(kubectl get pod -l app=sleep -n ${NAMESPACE} -o jsonpath={.items..metadata.name})" -n "${NAMESPACE}" -c sleep -- curl -s http://productpage.${NAMESPACE}.svc.cluster.local:9080/productpage | grep -qi "Simple Bookstore App"; then
  echo "SUCCESS: Request from ${NAMESPACE} namespace succeeded."
else
  echo "ERROR: Request from ${NAMESPACE} namespace failed!"
  exit 1
fi

echo "All mTLS tests passed!"