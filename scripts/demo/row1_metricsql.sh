#!/usr/bin/env bash
# Demo loader for VM Differentiators Row 1 (MetricsQL exclusive functions).
#
# Triggers conditions for:
#   #1 Manual z-score          -- needs RAG drift
#   #2 outliers_iqr             -- needs ONE model with outlier latency
#   #3 share_le_over_time      -- needs RAG drops below 0.85
#   #4 quantiles_over_time     -- already populates from gauge
#   #5 histogram_avg            -- already populates
#   #6 keep_last_value          -- already populates
set -e
VM_URL="${VM_URL:-http://localhost:8428}"
DURATION="${DURATION:-600}"   # 10 min

echo "=== Row 1 demo: injecting RAG drift + latency outlier on gpt-4o for ${DURATION}s ==="
echo

# 1. RAG drift -- restart simulator with score-drift
docker compose stop llm-simulator >/dev/null 2>&1 || true
docker rm -f llm-simulator-demo 2>/dev/null || true
docker compose run -d --name llm-simulator-demo --rm \
    llm-simulator --rps 10 --models 3 --score-drift 0.85 >/dev/null
echo "[OK] llm-simulator-demo started with score-drift=0.85"
echo "     -> Row 1 panels #1, #3, #6 will now show movement"

# 2. Latency outlier on gpt-4o via direct push
echo "[..] Pushing latency outlier on gpt-4o for ${DURATION}s (5s tick)"
END=$(( $(date +%s) + DURATION ))
while [ "$(date +%s)" -lt "$END" ]; do
    cat <<'EOF' | curl -s --data-binary @- "$VM_URL/api/v1/import/prometheus" >/dev/null
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="50"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="100"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="200"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="500"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="1000"} 1
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="2000"} 5
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="5000"} 50
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="10000"} 100
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="+Inf"} 100
llm_request_duration_ms_count{model="gpt-4o",provider="openai",pipeline_id="support-rag"} 100
llm_request_duration_ms_sum{model="gpt-4o",provider="openai",pipeline_id="support-rag"} 600000
EOF
    sleep 5
done

echo
echo "=== Row 1 demo complete. ==="
echo "Open http://localhost:3000/d/vm-diff -- Row 1 panels should now show:"
echo "  #1 z-score climbing (drift effect)"
echo "  #2 outliers_iqr lighting up gpt-4o (the slow model)"
echo "  #3 share_le_over_time growing %"
echo "Run 'make demo-clean' or 'bash scripts/demo/clean.sh' to revert."
