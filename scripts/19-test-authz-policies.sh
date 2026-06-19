#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-bookinfo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_DIR="${SCRIPT_DIR}/../policy"

echo "Applying AuthorizationPolicies to '${NAMESPACE}'..."
kubectl apply -n "${NAMESPACE}" -f "${POLICY_DIR}/authorization-policy-deny-all.yaml"
kubectl apply -n "${NAMESPACE}" -f "${POLICY_DIR}/authorization-policy-allow-productpage-to-reviews.yaml"
kubectl apply -n "${NAMESPACE}" -f "${POLICY_DIR}/authorization-policy-allow-productpage-to-details.yaml"
kubectl apply -n "${NAMESPACE}" -f "${POLICY_DIR}/authorization-policy-allow-reviews-to-ratings.yaml"
kubectl apply -n "${NAMESPACE}" -f "${POLICY_DIR}/authorization-policy-allow-ingress-to-productpage.yaml"

# Test clients impersonate each service's identity (via serviceAccountName) so that
# Istio's mTLS-derived principal matches what the AuthorizationPolicies check, without
# depending on curl being present in the bookinfo app images.
deploy_client() {
  local name="$1" service_account="$2"
  kubectl apply -n "${NAMESPACE}" -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: "${name}"
  labels:
    authz-test-client: "${name}"
spec:
  serviceAccountName: "${service_account}"
  containers:
  - name: curl
    image: curlimages/curl:8.10.1
    command: ["sleep", "infinity"]
EOF
}

echo "Deploying test client pods impersonating productpage, reviews, ratings and details identities..."
deploy_client authz-test-productpage bookinfo-productpage
deploy_client authz-test-reviews bookinfo-reviews
deploy_client authz-test-ratings bookinfo-ratings
deploy_client authz-test-details bookinfo-details

cleanup() {
  echo "Cleaning up test client pods..."
  kubectl delete pod authz-test-productpage authz-test-reviews authz-test-ratings authz-test-details \
    -n "${NAMESPACE}" --ignore-not-found=true --wait=false
}
trap cleanup EXIT

echo "Waiting for test client pods to be ready..."
kubectl wait --for=condition=ready pod authz-test-productpage authz-test-reviews authz-test-ratings authz-test-details \
  -n "${NAMESPACE}" --timeout=90s

echo "Waiting for policies to propagate..."
sleep 10

# run_test <pod> <url> <allow|deny> <description>
run_test() {
  local pod="$1" url="$2" expected="$3" description="$4"
  local code
  code="$(kubectl exec "${pod}" -n "${NAMESPACE}" -c curl -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${url}" || true)"

  if [[ "${expected}" == "allow" ]]; then
    if [[ "${code}" == "200" ]]; then
      echo "SUCCESS: ${description} (HTTP ${code})"
    else
      echo "ERROR: ${description} expected to be ALLOWED but got HTTP ${code}"
      exit 1
    fi
  else
    if [[ "${code}" == "200" ]]; then
      echo "ERROR: ${description} expected to be DENIED but got HTTP ${code}"
      exit 1
    else
      echo "SUCCESS: ${description} denied as expected (HTTP ${code})"
    fi
  fi
}

echo ""
echo "=== Testing ALLOWED communication ==="
run_test authz-test-productpage "http://reviews.${NAMESPACE}.svc.cluster.local:9080/reviews/0" allow "productpage -> reviews"
run_test authz-test-productpage "http://details.${NAMESPACE}.svc.cluster.local:9080/details/0" allow "productpage -> details"
run_test authz-test-reviews "http://ratings.${NAMESPACE}.svc.cluster.local:9080/ratings/0" allow "reviews -> ratings"

echo ""
echo "=== Testing BLOCKED communication ==="
run_test authz-test-ratings "http://reviews.${NAMESPACE}.svc.cluster.local:9080/reviews/0" deny "ratings -> reviews"
run_test authz-test-productpage "http://ratings.${NAMESPACE}.svc.cluster.local:9080/ratings/0" deny "productpage -> ratings"
run_test authz-test-details "http://reviews.${NAMESPACE}.svc.cluster.local:9080/reviews/0" deny "details -> reviews"

echo ""
echo "=== Testing ingress -> productpage remains reachable ==="
bash "${SCRIPT_DIR}/05-validate.sh"

echo ""
echo "All AuthorizationPolicy tests passed!"