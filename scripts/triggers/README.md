# Alert trigger scripts

One script per alert defined in `alerts/llm-quality.yml`. Each one drives the
stack into a state where the alert fires within its `for:` window, so you can
verify routing in the Alertmanager UI (http://localhost:9093) and in your
notification destination.

| Script                      | Alert                    | `for:` |
|-----------------------------|--------------------------|--------|
| `01_rag_index_drift.sh`     | RAGIndexDrift            | 15m    |
| `02_rag_context_pressure.sh`| RAGContextPressureHigh   | 5m     |
| `03_llm_high_error_rate.sh` | LLMHighErrorRate         | 3m     |
| `04_llm_latency_slo.sh`     | LLMLatencySLOBreach      | 5m     |
| `05_gpu_memory_sat.sh`      | GPUMemorySaturation      | 2m     |
| `06_llm_daily_budget.sh`    | LLMDailyBudgetWarning    | 0m     |
| `07_llm_ttft_high.sh`       | LLMTTFTHigh              | 5m     |

Run from the lab root:  `bash scripts/triggers/<name>.sh`

To stop the injection and restore the nominal simulator:
```
bash scripts/triggers/_restore.sh
```
