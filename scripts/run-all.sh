#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-bookinfo}"
CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"

PYTHON_EXEC="$(command -v python || command -v python3 || true)"
if [[ -z "${PYTHON_EXEC}" ]]; then
  echo "ERROR: python or python3 is required" >&2
  exit 1
fi

echo "Running 01-create-cluster.sh: create the kind cluster"
bash "${SCRIPT_DIR}/01-create-cluster.sh"
echo
echo "Running 02-install-istio.sh: install Istio control plane"
bash "${SCRIPT_DIR}/02-install-istio.sh"
echo
echo "Running 03-deploy-bookinfo.sh: deploy Bookinfo application and gateway"
bash "${SCRIPT_DIR}/03-deploy-bookinfo.sh"
echo
echo "Running 05-validate.sh: verify Bookinfo is reachable through the ingress"
bash "${SCRIPT_DIR}/05-validate.sh"
echo
echo "Running 06-install-metrics.sh: install Prometheus and Grafana"
bash "${SCRIPT_DIR}/06-install-metrics.sh"
echo
echo "Running 07-install-tracing.sh: install Jaeger, Kiali, and tracing"
bash "${SCRIPT_DIR}/07-install-tracing.sh"
echo
echo "Switching to canary reviews routing"
kubectl -n "${NAMESPACE}" delete virtualservice reviews-combined --ignore-not-found=true
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay.yaml" --ignore-not-found=true
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml" --ignore-not-found=true
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay-50-percent.yaml" --ignore-not-found=true
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-canary.yaml"
echo
echo "Running 10-verify-canary.sh: validate the reviews canary deployment"
bash "${SCRIPT_DIR}/10-verify-canary.sh"
echo
echo "Switching to header-based reviews routing"
kubectl -n "${NAMESPACE}" delete virtualservice reviews-canary --ignore-not-found=true
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/combined-virtual-service.yaml"
echo "Waiting for Istio to reconcile header routing..."
sleep 5
echo
echo "Running 11-test-header-routing.sh: exercise header-based reviews routing"
bash "${SCRIPT_DIR}/11-test-header-routing.sh"
echo
echo "Switching to latency fault injection: route jason to reviews v2 and inject a 7s delay on ratings"
kubectl -n "${NAMESPACE}" delete virtualservice reviews-combined --ignore-not-found=true
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/destination-rule-all.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay.yaml"
kubectl get virtualservices -n bookinfo
echo
echo "Running 13-test-latency-fault.sh: verify that the 7s ratings delay causes reviews to time out"
bash "${SCRIPT_DIR}/13-test-latency-fault.sh"
echo "Removing latency fault injection"
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay.yaml" --ignore-not-found=true
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml" --ignore-not-found=true
echo
echo "Switching to 50% latency fault: inject a 7s delay on half of all ratings requests"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay-50-percent.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml"
echo
echo "Running 14-test-percentage-fault.sh: verify that roughly 50% of reviews requests observe the delay"
bash "${SCRIPT_DIR}/14-test-percentage-fault.sh"
echo "Removing percentage fault injection"
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay-50-percent.yaml" --ignore-not-found=true
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml" --ignore-not-found=true
echo
echo "Applying retry and timeout configuration for reviews: 3s timeout with 3 retries on 5xx errors"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-timeout-3s.yaml"
echo
echo "Running 15-test-retry-mechanism.py: verify that the retry policy improves the success rate against 5xx faults"
"${PYTHON_EXEC}" "${SCRIPT_DIR}/15-test-retry-mechanism.py"
echo
echo "Applying circuit breaker configuration for ratings: max 1 connection, max 1 pending request"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/destination-rule-ratings-circuit-breaker.yaml"
echo
echo "Running 16-test-circuit-breaker.sh: verify that the circuit breaker trips under high concurrency load"
bash "${SCRIPT_DIR}/16-test-circuit-breaker.sh"
echo "Restoring default ratings destination rule"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/destination-rule-all.yaml"
echo
echo "Running 17-test-mtls.sh: verify strict mTLS enforcement"
bash "${SCRIPT_DIR}/17-test-mtls.sh"
echo
echo "Running 18-test-external-mtls.sh: verify external to internal traffic with mTLS"
bash "${SCRIPT_DIR}/18-test-external-mtls.sh"
echo
echo "Running 19-test-authz-policies.sh: verify AuthorizationPolicy allow/deny rules between services"
bash "${SCRIPT_DIR}/19-test-authz-policies.sh"
echo
echo "Done. Bookinfo is live at: http://localhost:31080/productpage"
echo "Grafana: http://localhost:3000"
echo "Kiali:   http://localhost:20001/kiali"
echo "Jaeger:  http://localhost:16686/jaeger"
