#!/usr/bin/env bash
# Demo loader for VM Differentiators Row 3 (OTel exponential histograms).
# Verifies the OTel pipeline is alive and pings llm-app harder for visible
# divergence between explicit (llm-simulator) and exponential (llm-app) histograms.
set -e
VM_URL="${VM_URL:-http://localhost:8428}"
APP_URL="${APP_URL:-http://localhost:8001}"

echo "=== Row 3 demo: verifying OTel pipeline ==="

# 1. Check llm-app health
if curl -fs "$APP_URL/health" >/dev/null 2>&1 ; then
    echo "[OK] llm-app is healthy at $APP_URL/health"
else
    echo "[FAIL] llm-app unreachable at $APP_URL"
    echo "       Run: docker compose logs --tail 30 llm-app"
    exit 1
fi

# 2. Check OTel-pushed metrics exist in VM
echo "[..] Counting OTel-derived series (service_name=llm-demo-app)"
COUNT=$(curl -fsG "$VM_URL/api/v1/query" \
    --data-urlencode 'query=count(llm_request_duration_ms_bucket{service_name="llm-demo-app"})' \
    | python3 -c "import sys,json; r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else 0)" 2>/dev/null || echo 0)

if [ "${COUNT:-0}" = "0" ]; then
    echo "[WARN] No OTel-pushed series found yet."
    echo "       Possible causes:"
    echo "       1. resource_to_telemetry_conversion: enabled NOT working"
    echo "       2. OTel collector not yet flushed (wait 10s and retry)"
    echo "       3. llm-traffic container not yet hitting llm-app"
    echo
    echo "[..] Forcing a quick burst against llm-app to populate OTel pipeline"
    for i in {1..30}; do
        curl -fs -X POST "$APP_URL/rag" \
             -H 'Content-Type: application/json' \
             -d '{"model":"gpt-4o","provider":"openai","tenant_id":"acme"}' \
             >/dev/null 2>&1 &
    done
    wait
    echo "[OK] 30 RAG requests sent. Wait 10s for OTel batch flush."
    sleep 10

    COUNT=$(curl -fsG "$VM_URL/api/v1/query" \
        --data-urlencode 'query=count(llm_request_duration_ms_bucket{service_name="llm-demo-app"})' \
        | python3 -c "import sys,json; r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else 0)" 2>/dev/null || echo 0)
fi

if [ "${COUNT:-0}" != "0" ]; then
    echo "[OK] $COUNT OTel-derived bucket series in VM"
else
    echo "[FAIL] Still no series. Inspect:"
    echo "       docker compose logs otel-collector --tail 50"
    echo "       Check that resource_to_telemetry_conversion: enabled is true"
fi

echo
echo "=== Row 3 demo complete. ==="
echo "Open http://localhost:3000/d/vm-diff -- Row 3 panels:"
echo "  #20 P99 explicit (llm-simulator)"
echo "  #21 P99 OTel path (llm-demo-app) -- both should now show data"
