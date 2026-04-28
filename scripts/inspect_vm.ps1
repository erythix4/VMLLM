# Probe every metric used in the VM Ops + VM Differentiators dashboards.
$vm = "http://localhost:8428"

function Probe($desc, $expr) {
    try {
        $body = "query=count($expr)" -replace ' ', '%20'
        $r = Invoke-RestMethod -Uri "$vm/api/v1/query?$body" -TimeoutSec 5
        if ($r.data.result.Count -gt 0) {
            "{0,5}  {1}" -f $r.data.result[0].value[1], $desc
        } else {
            "[EMPTY] {0}    expr: {1}" -f $desc, $expr
        }
    } catch {
        "[ERR  ] {0}    {1}" -f $desc, $_.Exception.Message
    }
}

Write-Host "VM at $vm -- probing every metric" -ForegroundColor Cyan
Write-Host ""
Write-Host "--- Cardinality ---"
Probe "vm_cache_entries (any)"             'vm_cache_entries'
Probe "vm_cache_entries hour_metric_ids"   'vm_cache_entries{type=~".*hour_metric_ids.*"}'
Probe "vm_rows_inserted_total"             'vm_rows_inserted_total'
Probe "vm_new_timeseries_created_total"    'vm_new_timeseries_created_total'

Write-Host ""
Write-Host "--- Storage / RAM ---"
Probe "vm_data_size_bytes (any)"           'vm_data_size_bytes'
Probe "process_resident_memory_bytes"      'process_resident_memory_bytes'

Write-Host ""
Write-Host "--- Query performance / Go runtime ---"
Probe "process_cpu_seconds_total"          'process_cpu_seconds_total'
Probe "go_goroutines"                      'go_goroutines'
Probe "up{}"                               'up'
Probe "vm_request_duration_seconds_bucket" 'vm_request_duration_seconds_bucket'
Probe "vm_http_requests_total"             'vm_http_requests_total'
Probe "vm_concurrent_select_current"       'vm_concurrent_select_current'

Write-Host ""
Write-Host "--- LLM / VM Differentiators ---"
Probe "llm_requests_total"                 'llm_requests_total'
Probe "rag_retrieval_score_avg"            'rag_retrieval_score_avg'
Probe "llm_request_duration_ms_bucket"     'llm_request_duration_ms_bucket'
Probe "service_name=llm-demo-app"          'llm_request_duration_ms_bucket{service_name="llm-demo-app"}'
Probe "llm_cost_usd_total"                 'llm_cost_usd_total'
Probe "llm:cost_usd:agg1h"                 '{__name__="llm:cost_usd:agg1h"}'
Probe "llm_demo_bad_metric"                'llm_demo_bad_metric'

Write-Host ""
Write-Host "--- Discovery: which vm_* metric names actually exist? ---"
try {
    $body = "query=count by (__name__) ({__name__=~'vm_.*'})"
    $r = Invoke-RestMethod -Uri "$vm/api/v1/query?$body" -TimeoutSec 10
    $r.data.result | Sort-Object {$_.metric.__name__} | ForEach-Object {
        "  {0,8}  {1}" -f $_.value[1], $_.metric.__name__
    } | Select-Object -First 40
} catch {
    Write-Host "  (could not list vm_* metrics)" -ForegroundColor Red
}
