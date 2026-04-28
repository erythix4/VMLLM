#!/usr/bin/env bash
# Trigger GPUMemorySaturation (FB_USED/FB_TOTAL > 90% for 2m)
DURATION=180 INTERVAL=5 bash "$(dirname "$0")/_push.sh" "$(cat <<'EOF'
DCGM_FI_DEV_FB_USED{gpu="0",UUID="GPU-aaaa",pod="vllm-0",namespace="llm",node="gpu-node-1"} 79872
DCGM_FI_DEV_FB_TOTAL{gpu="0",UUID="GPU-aaaa",pod="vllm-0",namespace="llm",node="gpu-node-1"} 81920
EOF
)"
