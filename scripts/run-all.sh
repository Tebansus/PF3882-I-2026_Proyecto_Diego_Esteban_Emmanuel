#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/01-create-cluster.sh"
bash "${SCRIPT_DIR}/02-install-istio.sh"
bash "${SCRIPT_DIR}/03-deploy-bookinfo.sh"
bash "${SCRIPT_DIR}/05-validate.sh"

echo
echo "Done. Bookinfo is live at: http://localhost:30080/productpage"
