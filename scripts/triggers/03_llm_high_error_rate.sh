#!/usr/bin/env bash
# Trigger LLMHighErrorRate (errors/requests > 1% for 3m)
DURATION=240 INTERVAL=10 bash "$(dirname "$0")/_push.sh" "$(cat <<'EOF'
llm_errors_total{model="gpt-4o",provider="openai",error_type="upstream",status_code="503"} 50
llm_requests_total{model="gpt-4o",provider="openai",pipeline_id="support-rag",status="error"} 50
EOF
)"
