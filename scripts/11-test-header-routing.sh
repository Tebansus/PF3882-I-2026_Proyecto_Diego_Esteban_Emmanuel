#!/usr/bin/env bash
set -euo pipefail

URL="${URL:-http://localhost:31080/api/v1/products/0/reviews}"
HEADER_NAME="${HEADER_NAME:-end-user}"
HEADER_VALUE="${HEADER_VALUE:-jason}"
HEADER_EXPECTED="${HEADER_EXPECTED:-v2}"
NO_HEADER_EXPECTED="${NO_HEADER_EXPECTED:-valid}"

PYTHON_EXEC="$(command -v python || command -v python3 || true)"
if [[ -z "${PYTHON_EXEC}" ]]; then
  echo "ERROR: python or python3 is required" >&2
  exit 1
fi

classify_response() {
  "${PYTHON_EXEC}" -c 'import json,sys
raw=sys.stdin.read()
try:
    data=json.loads(raw)
except Exception:
    print("invalid")
    sys.exit(0)
reviews=data.get("reviews") if isinstance(data, dict) else None
if not isinstance(reviews, list):
    print("invalid")
    sys.exit(0)
colors=[]
for review in reviews:
    if isinstance(review, dict):
        rating=review.get("rating")
        if isinstance(rating, dict):
            color=rating.get("color")
            if isinstance(color, str):
                colors.append(color.lower())
if not colors:
    print("v1")
elif "red" in colors:
    print("v3")
else:
    print("v2")'
}

pass_msg() { printf "  PASS  %s\n" "$1"; }
fail_msg() { printf "  FAIL  %s\n" "$1" >&2; }

run_test() {
  local name="$1"
  local extra_args=()
  local expected="$2"
  local attempt=1
  local max_attempts=5
  local response
  local version
  local result

  if [[ "$name" == "header" ]]; then
    extra_args=("-H" "${HEADER_NAME}: ${HEADER_VALUE}")
  fi

  echo "Testing ${name} request against ${URL}..."

  while [[ ${attempt} -le ${max_attempts} ]]; do
    response=$(curl -s --max-time 5 "${extra_args[@]}" "${URL}" || true)
    if [[ -n "${response}" ]]; then
      version=$(printf '%s' "${response}" | classify_response)
      if [[ "${expected}" == "valid" ]]; then
        if [[ "${version}" == "v1" || "${version}" == "v2" || "${version}" == "v3" ]]; then
          pass_msg "${name}: got ${version} as expected"
          return 0
        fi
        result="expected valid version, got ${version}"
      else
        if [[ "${version}" == "${expected}" ]]; then
          pass_msg "${name}: got ${version} as expected"
          return 0
        fi
        result="expected ${expected}, got ${version}"
      fi
    else
      result="empty response from ${URL}"
    fi

    if [[ ${attempt} -lt ${max_attempts} ]]; then
      echo "  RETRY ${attempt}/${max_attempts}: ${result}"
      sleep 1
      attempt=$((attempt + 1))
      continue
    fi

    fail_msg "${name}: ${result}"
    return 1
  done
}

if [[ "${HEADER_EXPECTED}" == "" || "${NO_HEADER_EXPECTED}" == "" ]]; then
  fail_msg "HEADER_EXPECTED and NO_HEADER_EXPECTED must not be empty"
  exit 1
fi

run_test "no-header" "${NO_HEADER_EXPECTED}"
run_test "header" "${HEADER_EXPECTED}"

echo
printf "Header routing test completed.\n"
