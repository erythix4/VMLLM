#!/usr/bin/env bash
# Quick diagnosis script: checks every link in the metrics chain.
# Usage:  bash diagnose.sh
set -u
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[FAIL]${NC} $*"; }

echo "=== 1. Container status ==="
docker compose ps

echo
echo "=== 2. Simulator: is /metrics serving? ==="
if curl -fs http://localhost:9100/metrics | head -5 ; then
    NLINES=$(curl -fs http://localhost:9100/metrics | grep -c '^llm_\|^rag_\|^DCGM_')
    ok "simulator exposes $NLINES LLM metric lines"
else
    err "simulator unreachable on :9100 — check 'docker compose logs llm-simulator'"
fi

echo
echo "=== 3. vmagent: did it scrape the simulator? ==="
SAMPLES=$(curl -fsG 'http://localhost:8428/api/v1/query' \
    --data-urlencode 'query=count(llm_requests_total)' \
    | python3 -c "import sys,json; r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else 0)" 2>/dev/null || echo 0)
if [ "${SAMPLES:-0}" != "0" ]; then
    ok "VictoriaMetrics has $SAMPLES llm_requests_total series"
else
    err "no llm_requests_total in VM yet — check 'docker compose logs vmagent | tail -50'"
fi

echo
echo "=== 4. Live request rate (req/min) ==="
RPM=$(curl -fsG 'http://localhost:8428/api/v1/query' \
    --data-urlencode 'query=sum(rate(llm_requests_total[1m]))*60' \
    | python3 -c "import sys,json; r=json.load(sys.stdin)['data']['result']; print(round(float(r[0]['value'][1]),1) if r else 0)" 2>/dev/null || echo 0)
if [ "${RPM%.*}" -gt 0 ] 2>/dev/null; then
    ok "ingestion live: ~$RPM req/min"
else
    warn "no live rate yet — wait 60-90 s after stack start, then retry"
fi

echo
echo "=== 5. OTel Collector status ==="
if docker compose logs --tail 20 otel-collector 2>&1 | grep -qi 'error\|fatal'; then
    err "OTel Collector logs contain errors:"
    docker compose logs --tail 20 otel-collector | grep -i 'error\|fatal' | head -5
else
    ok "OTel Collector log clean (last 20 lines)"
fi

echo
echo "=== 6. vmalert rules loaded ==="
RULES=$(curl -fs http://localhost:8880/api/v1/rules 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(len(g.get('rules',[])) for g in d['data']['groups']))" 2>/dev/null || echo 0)
if [ "${RULES:-0}" -gt 0 ]; then
    ok "$RULES alert/recording rules loaded in vmalert"
else
    warn "no rules loaded yet in vmalert"
fi

echo
echo "Done. If anything is FAIL, run:"
echo "  docker compose logs --tail 80 <service-name>"
