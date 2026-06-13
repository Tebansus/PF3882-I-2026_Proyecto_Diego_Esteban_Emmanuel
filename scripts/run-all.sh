#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-bookinfo}"
CLUSTER_NAME="${CLUSTER_NAME:-bookinfo}"

# Ensure any previously deployed load generator is stopped before starting.
bash "${SCRIPT_DIR}/09-stop-load-generator.sh" || true

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
echo "Done. Bookinfo is live at: http://localhost:31080/productpage"
echo "Grafana: http://localhost:3000"
echo "Kiali:   http://localhost:20001/kiali"
echo "Jaeger:  http://localhost:16686/jaeger"
echo
echo "Applying delay to ratings"
kubectl -n "${NAMESPACE}" delete virtualservice reviews-combined --ignore-not-found=true
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/destination-rule-all.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay.yaml"
kubectl get virtualservices -n bookinfo
bash "${SCRIPT_DIR}/13-test-latency-fault.sh"
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay.yaml" --ignore-not-found=true
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml" --ignore-not-found=true

kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay-50-percent.yaml"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml"
bash "${SCRIPT_DIR}/14-test-percentage-fault.sh"
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-ratings-test-delay-50-percent.yaml" --ignore-not-found=true
kubectl -n "${NAMESPACE}" delete -f "${SCRIPT_DIR}/../networking/virtual-service-reviews-test-v2.yaml" --ignore-not-found=true

echo "Building load generator image"
docker build -t bookinfo-loadgen:latest -f "${SCRIPT_DIR}/Dockerfile.loadgen" "${SCRIPT_DIR}"
echo "Loading load generator image into kind cluster"
kind load docker-image bookinfo-loadgen:latest --name "${CLUSTER_NAME}"
echo "Deploying load generator to cluster"
kubectl -n "${NAMESPACE}" apply -f "${SCRIPT_DIR}/load-generator-deploy.yaml"
echo
