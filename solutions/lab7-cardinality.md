# Lab 7 -- Cardinality observation & remediation (Module 11)
*Estimated 30 min · level: advanced*

LLM workloads are the canonical cardinality trap. `model × provider × tenant
× pipeline × trace_id` = quick path to series explosion. VM stays stable up
to ~10M active series, but you should still observe and remediate before you
get there.

## Detect: VM-native cardinality endpoints

VM exposes cardinality stats out of the box -- **no exporter needed**.

```bash
# Total active series
curl -s 'http://localhost:8428/api/v1/status/tsdb' | jq '.data | {totalSeries, totalLabelValuePairs}'

# Top 10 labels by cardinality (the noisy ones)
curl -s 'http://localhost:8428/api/v1/status/tsdb?topN=10' | jq '.data.seriesCountByLabelName'

# Top 10 metrics by series count
curl -s 'http://localhost:8428/api/v1/status/tsdb?topN=10' | jq '.data.seriesCountByMetricName'

# Top 10 label-value pairs eating series
curl -s 'http://localhost:8428/api/v1/status/tsdb?topN=10' | jq '.data.seriesCountByLabelValuePair'
```

Open the **`VM Ops`** Grafana dashboard -- everything above is plotted live.

## Reproduce: the classic mistake (trace_id label)

```bash
N=5000 bash scripts/cardinality_explosion.sh
```

Refresh `VM Ops`: `vm_cache_entries`, `vm_rows`, and the cardinality panel
spike. The "Top labels" panel now shows `trace_id` at the top. That's the
red flag.

## Remediate: 3 strategies that work

### A. Drop the offending label at ingestion (vmagent relabel)

```yaml
# Add to prometheus.yml under the offending scrape job:
  metric_relabel_configs:
    - regex: 'trace_id|request_id|session_id'
      action: labeldrop
```

Restart vmagent. New samples come in clean; existing series naturally roll off.

### B. Group fine-grained labels into coarse ones

```yaml
  metric_relabel_configs:
    - source_labels: [model]
      regex: 'gpt-(4|3.5).*'
      target_label: model_family
      replacement: 'gpt'
```

Now `model_family=gpt` aggregates 12 GPT versions into 1 series.

### C. Restrict tenant_id to cost metrics only

`tenant_id` is essential for billing but pointless on `llm_request_duration_ms`.
Use `metric_relabel_configs` to drop it from latency / token metrics:

```yaml
  metric_relabel_configs:
    - source_labels: [__name__]
      regex: 'llm_request_duration_ms.*|llm_tokens_total'
      action: labeldrop
      regex_label: 'tenant_id'
```

## Cleanup

```bash
curl -X POST 'http://localhost:8428/api/v1/admin/tsdb/delete_series?match[]={__name__="llm_demo_bad_metric"}'
```

## Production checklist

| Symptom (in VM Ops dashboard)               | Likely cause                       | Fix |
|---------------------------------------------|------------------------------------|-----|
| `vm_active_series` doubles overnight        | A rotating ID label was added      | Find via `seriesCountByLabelValuePair`, drop |
| `vm_cache_entries` saturates `--memory`     | Cache thrash from cardinality      | Add memory or drop labels |
| Query latency P99 climbs without traffic    | Index growth dominates             | Stream aggregation (Lab 8) |
| New tenant onboarding -> 10x series         | tenant_id propagated everywhere    | Restrict to cost-only metrics |

---

## See also -- VM Differentiators dashboard

Open Grafana http://localhost:3000 -> folder *LLM Observability* ->
**VM Differentiators -- Demo & Training** -> **Row 4 -- Cardinality observation**.

Each panel in that row corresponds to one query above. Use it to demo the
feature live during a POC instead of typing into vmui.
