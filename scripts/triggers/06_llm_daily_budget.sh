#!/usr/bin/env bash
# Trigger LLMDailyBudgetWarning (sum increase(llm_cost_usd_total[24h]) > 80 USD).
# The simulator's small cost rate would take days; we push a big counter.
DURATION=60 INTERVAL=10 bash "$(dirname "$0")/_push.sh" "$(cat <<'EOF'
llm_cost_usd_total{model="gpt-4o",provider="openai",tenant_id="acme",use_case="chat"} 95
EOF
)"
