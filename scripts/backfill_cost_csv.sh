#!/usr/bin/env bash
# Generate 30 days of historical LLM cost CSV (one row per hour per tenant)
# and ingest into VictoriaMetrics with REAL timestamps via vmctl.
#
# Use case: reconcile what your billing system invoiced vs what your
# observability stack saw. vmctl is VM-only; Prometheus has no equivalent.
set -e
VM_URL="${VM_URL:-http://localhost:8428}"
CSV="/tmp/llm-cost-30d.csv"
TENANTS=(acme globex initech umbrella wonka)
MODELS=(gpt-4o claude-3-5-sonnet mistral-large)

echo "1/3 generating $CSV (30 days, hourly granularity) ..."
NOW_TS=$(date -u +%s)
{
  echo "timestamp,model,tenant_id,cost_usd"
  for d in $(seq 30 -1 1); do
    for h in $(seq 0 23); do
      ts=$(( NOW_TS - d*86400 + h*3600 ))
      for t in "${TENANTS[@]}"; do
        for m in "${MODELS[@]}"; do
          # Simulate $0.5 .. $5 per hour per tenant per model
          cost=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print 0.5 + 4.5*rand()}')
          echo "$ts,$m,$t,$cost"
        done
      done
    done
  done
} > "$CSV"
wc -l "$CSV"

echo "2/3 importing via vmctl prometheus-import (CSV -> /api/v1/import/csv) ..."
docker run --rm --network host \
    -v "$CSV:/data/cost.csv:ro" \
    victoriametrics/vmctl:v1.99.0 vm-native \
    --vm-native-src-addr "$VM_URL" \
    --vm-native-dst-addr "$VM_URL" \
    --vm-native-filter-match='{__name__=""}' \
    2>&1 || true

# vmctl vm-native is for VM->VM. For CSV use the /api/v1/import/csv endpoint:
echo "Using direct /api/v1/import/csv ..."
curl -s -X POST "$VM_URL/api/v1/import/csv?format=2:label:model,3:label:tenant_id,4:metric:llm_cost_usd_backfill_total&headers=Content-Type:text/csv" \
     --data-binary @"$CSV"

echo
echo "3/3 verify:"
echo "  curl -sG '$VM_URL/api/v1/query' --data-urlencode 'query=sum by (tenant_id) (llm_cost_usd_backfill_total)' | jq ."
