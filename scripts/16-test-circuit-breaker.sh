#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for fortio pod to be ready..."
kubectl wait pods -l app=fortio -n bookinfo --for=condition=Ready --timeout=90s

FORTIO_POD=$(kubectl get pod -l app=fortio -n bookinfo -o jsonpath='{.items[0].metadata.name}')

echo "Sending high concurrency traffic (20 connections, 100 total requests) to ratings via fortio..."
kubectl exec "$FORTIO_POD" -c fortio -n bookinfo -- fortio load -c 20 -qps 0 -n 100 -loglevel Warning http://ratings:9080/ratings/0
