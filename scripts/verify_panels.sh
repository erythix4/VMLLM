#!/usr/bin/env bash
# For each Grafana panel in the 3 dashboards, hit VM /api/v1/query with its
# expression and report empty results.
set -e
VM_URL="${VM_URL:-http://localhost:8428}"
DASH_DIR="${DASH_DIR:-./grafana/dashboards}"

echo "Testing every panel query against $VM_URL ..."
echo
for dash in "$DASH_DIR"/*.json; do
    name=$(basename "$dash")
    echo "=== $name ==="
    python3 - "$dash" "$VM_URL" <<'PY'
import json, sys, urllib.parse, urllib.request

dash = json.load(open(sys.argv[1]))
vm   = sys.argv[2]
title = dash.get('title','?')

for panel in dash.get('panels', []):
    if panel.get('type') in ('row','text'): continue
    pid = panel.get('id')
    pt  = panel.get('title','?')
    for t in panel.get('targets', []) or []:
        expr = t.get('expr','')
        if not expr or expr.startswith('label_values'): continue
        # Replace dashboard variables with neutral wildcards
        expr2 = (expr
                 .replace('$model', '.*')
                 .replace('$provider', '.*')
                 .replace('$pipeline_id', '.*'))
        try:
            url = f"{vm}/api/v1/query?query={urllib.parse.quote(expr2)}"
            req = urllib.request.urlopen(url, timeout=5)
            data = json.load(req)
            n = len(data.get('data',{}).get('result',[]))
            tag = "OK   " if n > 0 else "EMPTY"
            print(f"  {tag} #{pid:3d} {pt[:60]:60s}  ({n} series)")
        except Exception as e:
            print(f"  ERR   #{pid:3d} {pt[:60]:60s}  -> {e}")
PY
    echo
done
