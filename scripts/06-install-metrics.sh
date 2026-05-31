#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Installing Prometheus..."
kubectl apply -f "${PROJECT_ROOT}/metrics/prometheus.yaml"

echo "Installing Bookinfo dashboard..."
kubectl apply -f "${PROJECT_ROOT}/metrics/bookinfo-dashboard.yaml"

echo "Installing Grafana..."
kubectl apply -f "${PROJECT_ROOT}/metrics/grafana.yaml"

echo "Waiting for metrics deployments to be available..."
kubectl wait deployment -n istio-system prometheus --for=condition=Available --timeout=120s
kubectl wait deployment -n istio-system grafana --for=condition=Available --timeout=120s

echo "Metrics stack installed successfully."
echo "You can access Grafana by running:"
echo "  kubectl -n istio-system port-forward svc/grafana 3000:3000"
echo "Then open http://localhost:3000 in your browser."
