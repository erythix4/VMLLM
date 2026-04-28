#!/usr/bin/env bash
# Trigger LLMLatencySLOBreach (P99 > 5000ms for 5m). Push lopsided histogram.
DURATION=420 INTERVAL=10 bash "$(dirname "$0")/_push.sh" "$(cat <<'EOF'
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="50"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="100"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="200"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="500"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="1000"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="2000"} 0
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="5000"} 1
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="10000"} 80
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="30000"} 100
llm_request_duration_ms_bucket{model="gpt-4o",provider="openai",pipeline_id="support-rag",le="+Inf"} 100
llm_request_duration_ms_count{model="gpt-4o",provider="openai",pipeline_id="support-rag"} 100
llm_request_duration_ms_sum{model="gpt-4o",provider="openai",pipeline_id="support-rag"} 800000
EOF
)"
