#!/usr/bin/env bash
# Lab 7 -- explode cardinality on purpose to demonstrate the
# remediation workflow described in solutions/lab7-cardinality.md.
#
# Pushes 5000 unique label combinations into VictoriaMetrics.
# Watch the impact in the "VM Ops" Grafana dashboard.
set -e
VM_URL="${VM_URL:-http://localhost:8428}"
N="${N:-5000}"

echo "Pushing $N high-cardinality samples into $VM_URL ..."
{
  for i in $(seq 1 "$N"); do
    # Each sample has a unique trace_id label -- the classic mistake
    echo "llm_demo_bad_metric{trace_id=\"$i\",tenant_id=\"t$((i % 100))\",pipeline_id=\"p$((i % 50))\"} 1"
  done
} | curl -s --data-binary @- "$VM_URL/api/v1/import/prometheus"

echo "Done. Now check:"
echo "  curl -s '$VM_URL/api/v1/status/tsdb' | jq ."
echo "  Grafana -> 'VM Ops' dashboard"
echo
echo "Cleanup:"
echo "  curl -X POST '$VM_URL/api/v1/admin/tsdb/delete_series?match[]={__name__=\"llm_demo_bad_metric\"}'"
