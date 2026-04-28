#!/usr/bin/env bash
# Demo loader for VM Differentiators Row 4 (cardinality explosion + remediation).
set -e

echo "=== Row 4 demo: explode cardinality with 5000 demo series ==="
bash "$(dirname "$0")/../cardinality_explosion.sh"

echo
echo "=== Row 4 demo complete. ==="
echo "Open http://localhost:3000/d/vm-diff -- Row 4 panels:"
echo "  #30 'Active series' jumps"
echo "  #31 'Lab 7 demo series count' shows 5000 -- panel goes red"
echo
echo "To clean up: bash scripts/demo/clean.sh  (or 'make lab7-cleanup')"
