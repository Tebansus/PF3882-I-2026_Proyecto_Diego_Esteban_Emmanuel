#!/usr/bin/env bash
set -euo pipefail

# Smoke test: hits productpage via the kind NodePort (31080) and checks that the
# response includes content from the details and reviews services.

HOST_PORT="${HOST_PORT:-31080}"
URL="${URL:-http://localhost:${HOST_PORT}/productpage}"

echo "Validating Istio installation..."
if ! kubectl get namespace istio-system >/dev/null 2>&1; then
  echo "FAIL: Istio not installed. Run scripts/02-install-istio.sh" >&2
  exit 1
fi

if ! kubectl wait --for=condition=Available --timeout=60s deployment/istiod -n istio-system >/dev/null 2>&1; then
  echo "FAIL: Istio control plane not ready" >&2
  exit 1
fi
echo "Istio control plane is ready."

echo "GET ${URL}"
HTTP_CODE=$(curl -s -o /tmp/bookinfo-productpage.html -w "%{http_code}" "${URL}" || true)

if [[ "${HTTP_CODE}" != "200" ]]; then
  echo "FAIL: expected HTTP 200, got '${HTTP_CODE}'" >&2
  echo "  - Is the cluster up?            scripts/01-create-cluster.sh"
  echo "  - Is the app deployed?          scripts/03-deploy-bookinfo.sh"
  echo "  - Are pods Ready?               kubectl -n bookinfo get pods"
  exit 1
fi

echo "HTTP 200 OK"

pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
FAILED=0

grep -q "Book Details" /tmp/bookinfo-productpage.html && pass "details service rendered" || fail "details service rendered"
grep -q "Book Reviews"  /tmp/bookinfo-productpage.html && pass "reviews service rendered" || fail "reviews service rendered"
grep -qi "<title>Simple Bookstore App</title>" /tmp/bookinfo-productpage.html && pass "productpage title present" || fail "productpage title present"

if [[ "${FAILED}" -ne 0 ]]; then
  echo
  echo "One or more checks failed. Saved response: /tmp/bookinfo-productpage.html"
  exit 1
fi

echo
echo "Bookinfo is reachable and rendering all upstream services."
echo "Open ${URL} in a browser to navigate the UI."
