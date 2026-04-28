#!/usr/bin/env bash
# Why is vmagent not scraping?
echo "=== vmagent container status ==="
docker compose ps vmagent

echo
echo "=== vmagent logs (last 30 lines) ==="
docker compose logs vmagent --tail 30

echo
echo "=== vmagent's view of its scrape targets ==="
docker exec vmagent-llm wget -qO- 'http://localhost:8429/api/v1/targets' 2>/dev/null \
  | python3 -m json.tool 2>/dev/null \
  | head -60 \
  || echo "Could not reach vmagent's API. Container probably not running OR port 8429 not exposed internally."

echo
echo "=== Reachability test from vmagent to victoriametrics ==="
docker exec vmagent-llm wget -qO- 'http://victoriametrics:8428/health' 2>/dev/null \
  && echo "OK victoriametrics:8428 reachable from vmagent" \
  || echo "FAIL: vmagent cannot reach victoriametrics:8428 (network issue)"

echo
echo "Common causes if vmagent is down or not scraping:"
echo "  1. Stream aggregation flag misconfigured (recent change)"
echo "  2. prometheus.yml syntax error"
echo "  3. Network: docker compose down -v + up to recreate the network"
