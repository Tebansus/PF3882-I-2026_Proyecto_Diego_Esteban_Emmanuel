#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-bookinfo}"
CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"

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
echo "Running 08-start-load-generator.sh: start the load generator"
bash "${SCRIPT_DIR}/08-start-load-generator.sh"
echo
echo "Switching to canary reviews routing"
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
echo "Running 11-test-header-routing.sh: exercise header-based reviews routing"
bash "${SCRIPT_DIR}/11-test-header-routing.sh"
echo
echo "Done. Bookinfo is live at: http://localhost:31080/productpage"
echo "Grafana: http://localhost:3000"
echo "Kiali:   http://localhost:20001/kiali"
echo "Jaeger:  http://localhost:16686/jaeger"
