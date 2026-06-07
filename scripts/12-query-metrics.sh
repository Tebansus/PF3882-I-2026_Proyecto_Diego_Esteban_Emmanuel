#!/usr/bin/env bash
set -euo pipefail

echo "Starting port-forward to Prometheus..."
kubectl port-forward -n istio-system svc/prometheus 9090:9090 > /dev/null 2>&1 &
PF_PID=$!

# Wait for port-forward to initialize
sleep 3

# Query traffic to reviews service
echo "Querying Prometheus for reviews service traffic split..."
QUERY='sum(rate(istio_requests_total{destination_service="reviews.bookinfo.svc.cluster.local"}[1m])) by (destination_workload)'
# urlencode the query
ENCODED_QUERY=$(python -c "import urllib.parse; print(urllib.parse.quote('''$QUERY'''))")

JSON_RESP=$(curl -s "http://localhost:9090/api/v1/query?query=${ENCODED_QUERY}" || echo "")

kill $PF_PID || true

if [ -z "$JSON_RESP" ]; then
    echo "Failed to fetch metrics from Prometheus."
    exit 1
fi

echo "Summary of traffic to reviews service (requests per second over last 5m):"
echo "$JSON_RESP" | python -c "
import sys, json
try:
    data = json.load(sys.stdin)
    total = 0
    results = {}
    for res in data.get('data', {}).get('result', []):
        metric = res['metric'].get('destination_workload', 'unknown')
        val = float(res['value'][1])
        results[metric] = val
        total += val
        
    for k, v in sorted(results.items()):
        pct = (v / total * 100) if total > 0 else 0
        print(f' - {k}: {v:.2f} rps ({pct:.1f}%)')
    
    if total == 0:
        print('No traffic observed.')
except Exception as e:
    print('Error parsing Prometheus response:', e)
"
