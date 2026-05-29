#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_DIR="${PROJECT_ROOT}/logs"
PID_FILE="${LOG_DIR}/load-generator.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "Load generator is not running."
  exit 0
fi

PID="$(cat "${PID_FILE}")"
if kill -0 "${PID}" >/dev/null 2>&1; then
  kill "${PID}"
  echo "Stopped load generator (pid ${PID})."
else
  echo "Load generator process not running."
fi

rm -f "${PID_FILE}"
