#!/usr/bin/env bash
# Revert all VM Differentiators demos
set -e
COMPOSE="${COMPOSE:-docker-compose.yml}"

echo "=== Cleaning up all demos ==="

# Stop demo simulator
docker rm -f llm-simulator-demo 2>/dev/null || true
docker compose start llm-simulator >/dev/null 2>&1 || true
echo "[OK] llm-simulator restored to nominal"

# Disable stream aggregation
sed -i "s|^      - '--remoteWrite.streamAggr|      # - '--remoteWrite.streamAggr|" "$COMPOSE" || true
docker compose restart vmagent >/dev/null 2>&1 || true
echo "[OK] stream aggregation disabled"

# Delete cardinality demo series
curl -s -X POST 'http://localhost:8428/api/v1/admin/tsdb/delete_series?match[]={__name__="llm_demo_bad_metric"}' >/dev/null 2>&1 || true
echo "[OK] cardinality demo series deleted"

# Kill any background row1 processes
pkill -f "row1_metricsql.sh" 2>/dev/null || true
echo "[OK] row1 background loop killed (if any)"

echo
echo "=== All demos reverted. Dashboard panels go back to nominal in 30-60s. ==="
