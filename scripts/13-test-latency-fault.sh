#!/usr/bin/env bash
set -euo pipefail

# Verifies the ratings fault-injection delay configured in
# networking/virtual-service-ratings-test-delay.yaml:
#   - end-user "jason" is routed to reviews-v2 (which calls ratings) and the
#     7s ratings delay trips productpage's hardcoded 3s timeout (x2 retries),
#     so the page takes ~6s and shows the "reviews unavailable" error.
#   - anonymous traffic is unaffected and renders reviews quickly.

NAMESPACE="${NAMESPACE:-bookinfo}"
HOST_PORT="${HOST_PORT:-31080}"
URL="${URL:-http://localhost:${HOST_PORT}}"
TEST_USER="${TEST_USER:-jason}"
MIN_DELAY="${MIN_DELAY:-5.5}"
CURL_MAX_TIME="${CURL_MAX_TIME:-15}"
MAX_BASELINE="${MAX_BASELINE:-2}"

COOKIE_JAR="$(mktemp)"
ANON_BODY="$(mktemp)"
USER_BODY="$(mktemp)"
trap 'rm -f "${COOKIE_JAR}" "${ANON_BODY}" "${USER_BODY}"' EXIT

pass_msg() { printf "  PASS  %s\n" "$1"; }
fail_msg() { printf "  FAIL  %s\n" "$1" >&2; FAILED=1; }
FAILED=0

echo "Checking that the 'ratings' VirtualService has the 7s fault delay..."
DELAY="$(kubectl -n "${NAMESPACE}" get virtualservice ratings \
  -o jsonpath='{.spec.http[0].fault.delay.fixedDelay}' 2>/dev/null || true)"
if [[ "${DELAY}" != "7s" ]]; then
  fail_msg "ratings VirtualService does not have a 7s fault delay (got '${DELAY:-<none>}')"
  echo "  Apply it with:" >&2
  echo "    kubectl apply -n ${NAMESPACE} -f networking/virtual-service-reviews-test-v2.yaml" >&2
  echo "    kubectl apply -n ${NAMESPACE} -f networking/virtual-service-ratings-test-delay.yaml" >&2
  exit 1
fi
pass_msg "ratings VirtualService injects a 7s delay for end-user: ${TEST_USER}"

echo
echo "Sending anonymous request to ${URL}/productpage..."
anon_time="$(curl -s -o "${ANON_BODY}" --max-time "${CURL_MAX_TIME}" -w "%{time_total}" "${URL}/productpage")"
echo "  response time: ${anon_time}s"

echo
echo "Logging in as '${TEST_USER}'..."
curl -s -o /dev/null -c "${COOKIE_JAR}" -d "username=${TEST_USER}" "${URL}/login"

echo "Sending request as '${TEST_USER}' to ${URL}/productpage..."
user_time="$(curl -s -o "${USER_BODY}" -b "${COOKIE_JAR}" --max-time "${CURL_MAX_TIME}" -w "%{time_total}" "${URL}/productpage")"
echo "  response time: ${user_time}s"

curl -s -o /dev/null -b "${COOKIE_JAR}" "${URL}/logout"

echo
echo "Results:"

if awk -v t="${anon_time}" -v max="${MAX_BASELINE}" 'BEGIN { exit !(t+0 <= max+0) }'; then
  pass_msg "anonymous request returned in ${anon_time}s (<= ${MAX_BASELINE}s)"
else
  fail_msg "anonymous request took ${anon_time}s, expected <= ${MAX_BASELINE}s"
fi

if grep -q "Sorry, product reviews are currently unavailable" "${ANON_BODY}"; then
  fail_msg "anonymous response unexpectedly shows the reviews-unavailable error"
else
  pass_msg "anonymous response renders reviews normally"
fi

if awk -v t="${user_time}" -v min="${MIN_DELAY}" 'BEGIN { exit !(t+0 >= min+0) }'; then
  pass_msg "${TEST_USER} request took ${user_time}s (>= ${MIN_DELAY}s, 7s ratings delay applied)"
else
  fail_msg "${TEST_USER} request took only ${user_time}s, expected >= ${MIN_DELAY}s"
fi

if grep -q "Sorry, product reviews are currently unavailable" "${USER_BODY}"; then
  pass_msg "${TEST_USER} response shows the reviews-unavailable error caused by the delay"
else
  fail_msg "${TEST_USER} response did not show the expected reviews-unavailable error"
fi

echo
if [[ "${FAILED}" -ne 0 ]]; then
  echo "Latency fault injection test FAILED."
  exit 1
fi

echo "Latency fault injection test PASSED."
