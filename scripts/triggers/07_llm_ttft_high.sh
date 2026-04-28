#!/usr/bin/env bash
# Trigger LLMTTFTHigh (TTFT P95 > 2000ms for 5m)
DURATION=420 INTERVAL=10 bash "$(dirname "$0")/_push.sh" "$(cat <<'EOF'
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="50"} 0
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="100"} 0
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="200"} 0
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="500"} 0
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="1000"} 0
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="2000"} 1
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="5000"} 80
llm_ttft_ms_bucket{model="gpt-4o",provider="openai",le="+Inf"} 100
llm_ttft_ms_count{model="gpt-4o",provider="openai"} 100
llm_ttft_ms_sum{model="gpt-4o",provider="openai"} 250000
EOF
)"
