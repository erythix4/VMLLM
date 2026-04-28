#!/usr/bin/env bash
# usage: _push.sh "<metric_lines>"
# pushes Prometheus exposition format directly into VictoriaMetrics.
set -euo pipefail
VM_URL="${VM_URL:-http://localhost:8428}"
DURATION="${DURATION:-300}"
INTERVAL="${INTERVAL:-10}"
LINES="$1"
end=$(( $(date +%s) + DURATION ))
echo "Pushing for ${DURATION}s every ${INTERVAL}s into $VM_URL ..."
while [ "$(date +%s)" -lt "$end" ]; do
  echo "$LINES" | curl -s --data-binary @- "$VM_URL/api/v1/import/prometheus"
  sleep "$INTERVAL"
done
echo "done."
