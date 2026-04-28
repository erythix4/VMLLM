#!/usr/bin/env bash
# Stop any drift simulator and restart the nominal one
set -e
docker rm -f llm-simulator-drift 2>/dev/null || true
docker compose start llm-simulator
echo "Restored nominal simulator. Alerts will resolve after their evaluation window."
