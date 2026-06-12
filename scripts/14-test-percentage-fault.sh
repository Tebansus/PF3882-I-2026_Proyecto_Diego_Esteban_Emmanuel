#!/usr/bin/env bash
set -euo pipefail

# Validates percentage-based fault injection on `ratings`
# (networking/virtual-service-ratings-test-delay-50-percent.yaml): unlike
# virtual-service-ratings-test-delay.yaml (100% delay for end-user: jason
# only), this rule applies a 7s delay to a configurable percentage of ALL
# traffic reaching `ratings`, regardless of who is calling.
#
# To observe it, traffic must reach `ratings`, so jason is routed to
# reviews-v2 (networking/virtual-service-reviews-test-v2.yaml). The load
# generator is run with --header-rate 1.0 so every request is "jason".
#
# productpage calls reviews with a hardcoded 3s timeout and up to 2 attempts
# (see src/productpage/productpage.py:getProductReviews), and each attempt
# makes its own independent call to ratings. This produces three latency
# clusters per /productpage request:
#   - ~0s   : 1st ratings call was NOT delayed -> reviews replies in time
#   - ~3s   : 1st ratings call WAS delayed (1st attempt times out) but the
#             2nd ratings call was NOT delayed
#   - ~6s   : both ratings calls were delayed -> productpage gives up and
#             shows "Sorry, product reviews are currently unavailable"
# The fraction of requests with elapsed >= LATENCY_THRESHOLD (set between the
# ~0s and ~3s clusters) equals P(1st ratings call delayed), i.e. the
# fault.delay.percentage.value configured on the ratings VirtualService.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="${NAMESPACE:-bookinfo}"
HOST_PORT="${HOST_PORT:-31080}"
URL="${URL:-http://localhost:${HOST_PORT}/productpage}"
DURATION="${DURATION:-60}"
THREADS="${THREADS:-4}"
DELAY_MIN="${DELAY_MIN:-0.1}"
DELAY_MAX="${DELAY_MAX:-0.5}"
LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-1.5}"
TOLERANCE="${TOLERANCE:-0.15}"

LOG_DIR="${PROJECT_ROOT}/logs"
LATENCY_LOG="${LOG_DIR}/14-latency-fault-percentage.csv"
RUN_LOG="${LOG_DIR}/14-test-percentage-fault.log"

pass_msg() { printf "  PASS  %s\n" "$1"; }
fail_msg() { printf "  FAIL  %s\n" "$1" >&2; FAILED=1; }
FAILED=0

PYTHON_EXEC="$(command -v python3 || command -v python || true)"
if [[ -z "${PYTHON_EXEC}" ]]; then
  echo "ERROR: python or python3 is required" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

echo "Applying VirtualServices for the percentage-based fault test..."
kubectl apply -n "${NAMESPACE}" -f "${PROJECT_ROOT}/networking/virtual-service-reviews-test-v2.yaml" >/dev/null
kubectl apply -n "${NAMESPACE}" -f "${PROJECT_ROOT}/networking/virtual-service-ratings-test-delay-50-percent.yaml" >/dev/null

EXPECTED_PCT="$(kubectl -n "${NAMESPACE}" get virtualservice ratings \
  -o jsonpath='{.spec.http[0].fault.delay.percentage.value}' 2>/dev/null || true)"
DELAY="$(kubectl -n "${NAMESPACE}" get virtualservice ratings \
  -o jsonpath='{.spec.http[0].fault.delay.fixedDelay}' 2>/dev/null || true)"

if [[ -z "${EXPECTED_PCT}" || "${DELAY}" != "7s" ]]; then
  fail_msg "ratings VirtualService does not have a percentage-based 7s fault delay configured"
  exit 1
fi
pass_msg "ratings VirtualService injects a 7s delay on ${EXPECTED_PCT}% of traffic"

echo
echo "Running load generator for ${DURATION}s as end-user: jason against ${URL}..."
rm -f "${LATENCY_LOG}"
"${PYTHON_EXEC}" "${PROJECT_ROOT}/scripts/load-generator.py" \
  --url "${URL}" \
  --threads "${THREADS}" \
  --delay-min "${DELAY_MIN}" \
  --delay-max "${DELAY_MAX}" \
  --header-rate 1.0 \
  --latency-log "${LATENCY_LOG}" \
  --latency-threshold "${LATENCY_THRESHOLD}" \
  --stats-interval 10 \
  > "${RUN_LOG}" 2>&1 &
LG_PID=$!

sleep "${DURATION}"
kill "${LG_PID}" 2>/dev/null || true
wait "${LG_PID}" 2>/dev/null || true

echo "Load generator log: ${RUN_LOG}"
echo "Latency samples:    ${LATENCY_LOG}"

if [[ ! -s "${LATENCY_LOG}" ]]; then
  fail_msg "no latency samples captured in ${LATENCY_LOG}"
  exit 1
fi

echo
if "${PYTHON_EXEC}" - "${LATENCY_LOG}" "${LATENCY_THRESHOLD}" "${EXPECTED_PCT}" "${TOLERANCE}" <<'PY'
import csv
import sys

path, threshold, expected_pct, tolerance = (
    sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
)

total = 0
slow = 0
with open(path, newline="") as f:
    for row in csv.DictReader(f):
        total += 1
        if float(row["elapsed"]) >= threshold:
            slow += 1

if total == 0:
    print("No samples recorded.")
    sys.exit(1)

ratio = slow / total
expected = expected_pct / 100.0
lo, hi = max(0.0, expected - tolerance), min(1.0, expected + tolerance)

print(f"Samples: {total}  Delayed (elapsed >= {threshold}s): {slow} ({ratio:.1%})")
print(f"Expected delay rate: {expected:.0%}  (tolerance +/-{tolerance:.0%}, range {lo:.0%}-{hi:.0%})")

sys.exit(0 if lo <= ratio <= hi else 1)
PY
then
  pass_msg "observed delay rate matches the configured ${EXPECTED_PCT}% fault percentage"
else
  fail_msg "observed delay rate does not match the configured ${EXPECTED_PCT}% fault percentage"
fi

echo
if [[ "${FAILED}" -ne 0 ]]; then
  echo "Percentage-based fault injection test FAILED."
  exit 1
fi

echo "Percentage-based fault injection test PASSED."
echo
echo "To remove the fault:"
echo "  kubectl delete -n ${NAMESPACE} -f ${PROJECT_ROOT}/networking/virtual-service-ratings-test-delay-50-percent.yaml"
echo "  kubectl delete -n ${NAMESPACE} -f ${PROJECT_ROOT}/networking/virtual-service-reviews-test-v2.yaml"
