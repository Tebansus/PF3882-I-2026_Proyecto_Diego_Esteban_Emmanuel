#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for fortio pod to be ready..."
kubectl wait pods -l app=fortio -n bookinfo --for=condition=Ready --timeout=90s

FORTIO_POD=$(kubectl get pod -l app=fortio -n bookinfo -o jsonpath='{.items[0].metadata.name}')
