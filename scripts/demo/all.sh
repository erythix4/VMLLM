#!/usr/bin/env bash
# Demo loader for the WHOLE VM Differentiators dashboard.
# Triggers conditions for all 4 rows so every panel shows something within ~2 min.
set -e
DIR=$(dirname "$0")

echo "================================================================"
echo "Running VM Differentiators FULL demo"
echo "================================================================"

# Start row 1 in background (it has a 10-min loop)
DURATION=600 bash "$DIR/row1_metricsql.sh" &
ROW1_PID=$!
echo "[OK] Row 1 started in background (PID $ROW1_PID, ~10 min)"

bash "$DIR/row2_streamaggr.sh"
echo
bash "$DIR/row3_otel.sh"
echo
bash "$DIR/row4_cardinality.sh"

echo
echo "================================================================"
echo "All rows seeded. Open http://localhost:3000/d/vm-diff and wait 60s."
echo "Row 1 demo loop is still running for ~10 min as background PID $ROW1_PID."
echo "Run 'bash scripts/demo/clean.sh' to revert everything."
echo "================================================================"
