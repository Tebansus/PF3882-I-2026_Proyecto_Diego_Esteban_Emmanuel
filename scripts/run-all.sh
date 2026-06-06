#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/01-create-cluster.sh"
bash "${SCRIPT_DIR}/02-install-istio.sh"
bash "${SCRIPT_DIR}/03-deploy-bookinfo.sh"
bash "${SCRIPT_DIR}/05-validate.sh"
bash "${SCRIPT_DIR}/06-install-metrics.sh"
bash "${SCRIPT_DIR}/07-install-tracing.sh"
bash "${SCRIPT_DIR}/08-start-load-generator.sh"

echo
echo "Done. Bookinfo is live at: http://localhost:31080/productpage"
echo "Grafana: http://localhost:3000"
echo "Kiali:   http://localhost:20001/kiali"
echo "Jaeger:  http://localhost:16686/jaeger"
