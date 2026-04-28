#!/usr/bin/env bash
# Demo loader for VM Differentiators Row 2 (vmagent stream aggregation).
set -e
COMPOSE="${COMPOSE:-docker-compose.yml}"

if grep -q "^      - '--remoteWrite.streamAggr" "$COMPOSE" ; then
    echo "[OK] stream aggregation already enabled in $COMPOSE"
else
    echo "[..] Enabling --streamAggr.config flag in vmagent"
    sed -i "s|^      # - '--remoteWrite.streamAggr|      - '--remoteWrite.streamAggr|" "$COMPOSE"
fi

echo "[..] Restarting vmagent"
docker compose restart vmagent >/dev/null

echo
echo "=== Row 2 demo complete. ==="
echo "Wait ~60s, then in vmui try:"
echo "  llm:cost_usd:agg1h"
echo "  llm:requests:agg1m"
echo "  llm:tokens:agg1m"
echo "Open http://localhost:3000/d/vm-diff -- Row 2 panels:"
echo "  #10 raw vs aggregated cardinality (green line appears)"
echo "  #12 'Stream aggr active?' switches to ON"
