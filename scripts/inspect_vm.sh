#!/usr/bin/env bash
# Probe every metric used in the VM Ops dashboard and report what's empty.
# Run this and paste the output if any panel stays flat.
set -e
VM="${VM_URL:-http://localhost:8428}"

probe() {
    local desc="$1" expr="$2"
    local count
    count=$(curl -fsG "$VM/api/v1/query" --data-urlencode "query=count($expr)" 2>/dev/null \
        | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 0)" 2>/dev/null \
        || echo "ERR")
    if [ "$count" = "0" ] || [ "$count" = "ERR" ]; then
        printf "  [EMPTY] %-50s  %s\n" "$desc" "$expr"
    else
        printf "  [%5s] %-50s\n" "$count" "$desc"
    fi
}

echo "================================================================"
echo "VM at $VM -- probing every metric used in VM Ops dashboard"
echo "================================================================"

echo
echo "--- Section 1: Cardinality panels ---"
probe "vm_cache_entries (any type)"               'vm_cache_entries'
probe "vm_cache_entries hour_metric_ids"          'vm_cache_entries{type=~".*hour_metric_ids.*"}'
probe "vm_rows_inserted_total"                    'vm_rows_inserted_total'
probe "vm_new_timeseries_created_total"           'vm_new_timeseries_created_total'
probe "vm_new_timeseries_created (alt name)"      'vm_new_timeseries_created'

echo
echo "--- Section 2: Storage & RAM ---"
probe "vm_data_size_bytes (any)"                  'vm_data_size_bytes'
probe "vm_data_size_bytes storage/data"           'vm_data_size_bytes{type=~".*data.*"}'
probe "process_resident_memory_bytes (vm only)"   'process_resident_memory_bytes{job="victoriametrics"}'
probe "process_resident_memory_bytes (any job)"   'process_resident_memory_bytes'

echo
echo "--- Section 3: Query performance ---"
probe "process_cpu_seconds_total"                  'process_cpu_seconds_total{job=~"victoriametrics|vmagent|vmalert"}'
probe "go_goroutines"                              'go_goroutines{job=~"victoriametrics|vmagent|vmalert"}'
probe "up{} synthetic"                             'up'
probe "vm_request_duration_seconds_bucket"        'vm_request_duration_seconds_bucket'
probe "vm_request_duration_seconds_sum"           'vm_request_duration_seconds_sum'
probe "vm_http_requests_total"                    'vm_http_requests_total'
probe "vm_concurrent_select_current"              'vm_concurrent_select_current'

echo
echo "--- Section 4: VM Differentiators dashboard queries ---"
probe "llm_requests_total"                        'llm_requests_total'
probe "rag_retrieval_score_avg"                   'rag_retrieval_score_avg'
probe "llm_request_duration_ms_bucket"            'llm_request_duration_ms_bucket'
probe "service_name=llm-demo-app (OTel path)"     'llm_request_duration_ms_bucket{service_name="llm-demo-app"}'
probe "llm_cost_usd_total"                        'llm_cost_usd_total'
probe "llm:cost_usd:agg1h (stream aggr)"          '{__name__="llm:cost_usd:agg1h"}'
probe "llm_demo_bad_metric (Lab 7)"               'llm_demo_bad_metric'

echo
echo "--- Discovery: list ALL vm_* metrics actually exposed ---"
echo "(curl-fetching /metrics endpoint directly; only first 30 unique names)"
docker exec vm-llm wget -qO- http://localhost:8428/metrics 2>/dev/null \
  | grep -E "^vm_" | sed 's/{.*//;s/ .*//' | sort -u | head -30 \
  || echo "  (could not fetch /metrics from vm-llm container)"

echo
echo "================================================================"
echo "Send this output to fix any panel that shows [EMPTY]."
echo "================================================================"
