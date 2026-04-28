#!/usr/bin/env bash
# Why is service_name=llm-demo-app empty?
set -e
VM="${VM_URL:-http://localhost:8428}"

echo "=== llm-app health ==="
docker exec llm-app wget -qO- http://localhost:8000/health 2>/dev/null \
    && echo " <- OK" \
    || echo "FAIL: llm-app not reachable from inside its container"

echo
echo "=== llm-traffic generating requests? ==="
docker compose logs llm-traffic --tail 5

echo
echo "=== List ALL labels present on llm_request_duration_ms_bucket ==="
echo "(this tells us if service_name OR a different label exists)"
curl -fsG "$VM/api/v1/series" --data-urlencode 'match[]=llm_request_duration_ms_bucket' 2>/dev/null \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)['data']
labels = set()
for s in d[:5]:
    labels.update(s.keys())
print('Sample 1:', d[0] if d else 'EMPTY')
print()
print('All label names seen:', sorted(labels))
"

echo
echo "=== OTel collector logs (last 20 lines) ==="
docker compose logs otel-collector --tail 20 | grep -Ev "INFO.*MetricsExporter" || true
