#!/usr/bin/env bash
# Trigger RAGContextPressureHigh (P95 rag_context_pressure_ratio > 0.85 for 5m)
DURATION=420 INTERVAL=10 bash "$(dirname "$0")/_push.sh" "$(cat <<'EOF'
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.1"} 0
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.3"} 0
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.5"} 0
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.7"} 0
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.8"} 0
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.85"} 0
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.9"} 5
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="0.95"} 50
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="1.0"} 100
rag_context_pressure_ratio_bucket{pipeline_id="support-rag",model="gpt-4o",le="+Inf"} 100
rag_context_pressure_ratio_count{pipeline_id="support-rag",model="gpt-4o"} 100
rag_context_pressure_ratio_sum{pipeline_id="support-rag",model="gpt-4o"} 95
EOF
)"
