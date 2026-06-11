#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST_PORT="${HOST_PORT:-31080}"
URL="${URL:-http://localhost:${HOST_PORT}/productpage}"
THREADS="${THREADS:-5}"
DELAY_MIN="${DELAY_MIN:-0.1}"
DELAY_MAX="${DELAY_MAX:-1.0}"
HEADER_RATE="${HEADER_RATE:-0.2}"
LATENCY_LOG="${LATENCY_LOG:-}"
LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-4.0}"
STATS_INTERVAL="${STATS_INTERVAL:-10}"

LOG_DIR="${PROJECT_ROOT}/logs"
PID_FILE="${LOG_DIR}/load-generator.pid"
LOG_FILE="${LOG_DIR}/load-generator.log"

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "ERROR: python/python3 not found in PATH." >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

if [[ -f "${PID_FILE}" ]]; then
  PID="$(cat "${PID_FILE}")"
  if kill -0 "${PID}" >/dev/null 2>&1; then
    echo "Load generator already running (pid ${PID})."
    exit 0
  fi
fi

LATENCY_ARGS=()
if [[ -n "${LATENCY_LOG}" ]]; then
  LATENCY_ARGS+=(--latency-log "${LATENCY_LOG}")
fi

echo "Starting load generator against ${URL}..."
$PYTHON "${PROJECT_ROOT}/scripts/load-generator.py" \
  --url "${URL}" \
  --threads "${THREADS}" \
  --delay-min "${DELAY_MIN}" \
  --delay-max "${DELAY_MAX}" \
  --header-rate "${HEADER_RATE}" \
  --latency-threshold "${LATENCY_THRESHOLD}" \
  --stats-interval "${STATS_INTERVAL}" \
  "${LATENCY_ARGS[@]}" \
  > "${LOG_FILE}" 2>&1 &

PID="$!"
echo "${PID}" > "${PID_FILE}"

echo "Load generator started (pid ${PID})."
echo "Logs: ${LOG_FILE}"
