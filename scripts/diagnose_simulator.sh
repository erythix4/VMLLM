#!/usr/bin/env bash
echo "=== Which simulator container is running? ==="
docker ps --filter "name=llm-simulator" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo
echo "=== Direct probe of simulator /metrics endpoint ==="
echo "(showing rag_* metric lines)"
curl -s http://localhost:9100/metrics 2>/dev/null | grep -E "^(rag_|llm_)" | head -10
test ${PIPESTATUS[0]} -eq 0 || echo "FAIL: simulator unreachable on :9100"

echo
echo "=== Demo simulator (if running) -- internal IP probe ==="
DEMO=$(docker ps -q --filter "name=llm-simulator-demo")
if [ -n "$DEMO" ]; then
    echo "Demo simulator is running ($DEMO). Its metrics:"
    docker exec "$DEMO" wget -qO- http://localhost:9100/metrics 2>/dev/null | grep -E "^rag_" | head -5
fi
