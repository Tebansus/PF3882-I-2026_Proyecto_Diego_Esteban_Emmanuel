#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST_PORT="${HOST_PORT:-31080}"
URL="${URL:-http://localhost:${HOST_PORT}/productpage}"
THREADS="${THREADS:-5}"
DELAY_MIN="${DELAY_MIN:-0.1}"
DELAY_MAX="${DELAY_MAX:-1.0}"

LOG_DIR="${PROJECT_ROOT}/logs"
PID_FILE="${LOG_DIR}/load-generator.pid"
LOG_FILE="${LOG_DIR}/load-generator.log"

if ! command -v python >/dev/null 2>&1; then
  echo "ERROR: python not found in PATH." >&2
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

echo "Starting load generator against ${URL}..."
python "${PROJECT_ROOT}/scripts/load-generator.py" \
  --url "${URL}" \
  --threads "${THREADS}" \
  --delay-min "${DELAY_MIN}" \
  --delay-max "${DELAY_MAX}" \
  > "${LOG_FILE}" 2>&1 &

PID="$!"
echo "${PID}" > "${PID_FILE}"

echo "Load generator started (pid ${PID})."
echo "Logs: ${LOG_FILE}"
