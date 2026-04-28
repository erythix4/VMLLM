#!/usr/bin/env bash
# Trigger RAGIndexDrift (avg_over_time(rag_retrieval_score_avg[1h]) < 0.70 for 15m)
set -e
docker compose stop llm-simulator
docker compose run -d --name llm-simulator-drift llm-simulator --rps 10 --models 3 --score-drift 0.5
echo "Drift simulator running. Alert fires after ~15 min."
echo "Restore with: bash scripts/triggers/_restore.sh"
