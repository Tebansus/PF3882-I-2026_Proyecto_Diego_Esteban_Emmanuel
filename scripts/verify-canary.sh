#!/usr/bin/env bash
set -euo pipefail

URL="${URL:-http://localhost:30080}"
SAMPLES="${SAMPLES:-100}"
TOLERANCE="${TOLERANCE:-0.05}"
ENDPOINT="${URL%/}/api/v1/products/0/reviews"

v1=0
v2=0
v3=0
errors=0

classify_response() {
  python -c 'import json,sys
raw = sys.stdin.read()
try:
  data = json.loads(raw)
except Exception:
  print("error")
  sys.exit(0)

reviews = data.get("reviews") if isinstance(data, dict) else None
if not isinstance(reviews, list):
  print("error")
  sys.exit(0)

colors = []
for review in reviews:
  rating = review.get("rating") if isinstance(review, dict) else None
  if isinstance(rating, dict):
    color = rating.get("color")
    if isinstance(color, str):
      colors.append(color.lower())

if not colors:
  print("v1")
elif "red" in colors:
  print("v3")
else:
  print("v2")
'
}

for _ in $(seq 1 "${SAMPLES}"); do
  resp="$(curl -s --max-time 5 "${ENDPOINT}" || true)"
  if [[ -z "${resp}" ]]; then
    errors=$((errors + 1))
    continue
  fi

  result="$(printf "%s" "${resp}" | classify_response)"
  case "${result}" in
    v1) v1=$((v1 + 1)) ;;
    v2) v2=$((v2 + 1)) ;;
    v3) v3=$((v3 + 1)) ;;
    *) errors=$((errors + 1)) ;;
  esac
  sleep 0.05
done

total=$((v1 + v2 + v3))
if [[ "${total}" -eq 0 ]]; then
  echo "No valid responses. Errors: ${errors}"
  exit 1
fi

python - <<PY
v1=${v1}
v2=${v2}
v3=${v3}
errors=${errors}
total=${total}
tol=${TOLERANCE}

canary = v2 + v3
canary_ratio = canary / total
min_ok = 0.10 - tol
max_ok = 0.10 + tol
status = "PASS" if min_ok <= canary_ratio <= max_ok else "FAIL"

print(f"Total valid: {total} (errors: {errors})")
print(f"v1: {v1}  v2: {v2}  v3: {v3}")
print(f"Canary ratio (v2+v3): {canary_ratio:.2%}  Expected: 10% +/- {tol:.0%} -> {status}")

if status != "PASS":
    raise SystemExit(2)
PY
