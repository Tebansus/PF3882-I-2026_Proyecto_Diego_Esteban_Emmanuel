#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for fortio pod to be ready..."
kubectl wait pods -l app=fortio -n bookinfo --for=condition=Ready --timeout=90s

FORTIO_POD=$(kubectl get pod -l app=fortio -n bookinfo -o jsonpath='{.items[0].metadata.name}')

echo "Fetching initial pending overflow stats from fortio..."
INITIAL_OVERFLOW=$(kubectl exec "$FORTIO_POD" -c istio-proxy -n bookinfo -- curl -s localhost:15000/stats | grep -E "cluster.outbound\|9080\|.*ratings.bookinfo.svc.cluster.local.upstream_rq_pending_overflow" | cut -d ":" -f 2 | tr -d " " | awk '{s+=$1} END {print s}')
INITIAL_OVERFLOW=${INITIAL_OVERFLOW:-0}
echo "Initial overflow: $INITIAL_OVERFLOW"

echo "Sending high concurrency traffic (20 connections, 100 total requests) to ratings via fortio..."
kubectl exec "$FORTIO_POD" -c fortio -n bookinfo -- fortio load -c 20 -qps 0 -n 100 -loglevel Warning http://ratings:9080/ratings/0

echo "Fetching final pending overflow stats..."
FINAL_OVERFLOW=$(kubectl exec "$FORTIO_POD" -c istio-proxy -n bookinfo -- curl -s localhost:15000/stats | grep -E "cluster.outbound\|9080\|.*ratings.bookinfo.svc.cluster.local.upstream_rq_pending_overflow" | cut -d ":" -f 2 | tr -d " " | awk '{s+=$1} END {print s}')
FINAL_OVERFLOW=${FINAL_OVERFLOW:-0}
echo "Final overflow: $FINAL_OVERFLOW"

if [ "$FINAL_OVERFLOW" -gt "$INITIAL_OVERFLOW" ]; then
    echo "SUCCESS: Circuit breaker was tripped! (Overflow increased from $INITIAL_OVERFLOW to $FINAL_OVERFLOW)"
    exit 0
else
    echo "FAILED: Circuit breaker did not trip. Overflow remained at $FINAL_OVERFLOW"
    exit 1
fi
