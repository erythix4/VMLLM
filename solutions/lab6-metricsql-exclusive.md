# Lab 6 -- MetricsQL functions PromQL cannot do
*Estimated 30 min · level: intermediate*

This lab is the "why VM" defense in 6 queries. Each one solves a real LLM
observability problem and **does not work on Prometheus / Mimir / Cortex with
PromQL** -- you'd have to build the workaround yourself.

Open vmui (http://localhost:8428/vmui) and run them one by one.

---

## 1. `anomaly_score` -- baseline-aware drift, no thresholds to tune

```promql
anomaly_score(
    avg by (index_id) (rag_retrieval_score_avg),
    "1h"
)
```

Returns the **z-score** of the current value vs its rolling 1-hour baseline.
`> 1` = significant deviation. No need to set `< 0.7` thresholds that drift
when the index is updated -- the baseline self-adjusts.

PromQL alternative: `(x - avg_over_time(x[1h])) / stddev_over_time(x[1h])`
written every time you need it, with explicit clamp_min for divide-by-zero.

---

## 2. `outliers_iqr` -- find requests whose latency is statistically abnormal

```promql
outliers_iqr(
    histogram_quantile(0.5,
        sum by (le, model) (rate(llm_request_duration_ms_bucket[5m]))
    )
)
```

Returns only the model series whose median latency falls outside the
inter-quartile-range fence (Q1 - 1.5·IQR, Q3 + 1.5·IQR). Lights up the model
that just broke without flooding the dashboard.

PromQL alternative: there is none. You'd export the data to a notebook.

---

## 3. `share_le_over_time` -- "% of time RAG quality stayed below SLO"

```promql
share_le_over_time(
    rag_retrieval_score_avg[1h],
    0.70
)
```

Direct answer to "what fraction of the last hour was the index degraded?"
Returns 0..1. Perfect for SLO error-budget panels.

PromQL alternative: `count_over_time(...{score < 0.7}[1h]) / count_over_time(...[1h])`
**doesn't work** -- gauge selectors don't apply per-sample.

---

## 4. `quantiles_over_time` -- P50/P95/P99 from a gauge in one query

```promql
quantiles_over_time("p50,p95,p99",
    rag_retrieval_score_avg[30m]
)
```

Returns three series in one query, labelled by `quantile`. For gauges that
aren't histograms (retrieval scores, GPU power, queue depth).

PromQL alternative: 3 separate `quantile_over_time(...)` queries, manually
labelled.

---

## 5. `histogram_avg` -- mean from a histogram, the right way

```promql
histogram_avg(rate(llm_request_duration_ms_bucket[5m]))
```

Emits one series per labelset, equal to `sum/count` from the histogram, but
respecting bucket midpoints. Cleaner than `rate(_sum) / rate(_count)` which
breaks on label mismatch.

PromQL alternative: `rate(x_sum[5m]) / rate(x_count[5m])` -- works only if
sum and count have identical label sets, which OTel-derived histograms often
violate.

---

## 6. `keep_last_value` -- handle scrape gaps without false alerts

```promql
keep_last_value(rag_retrieval_score_avg, 5m)
```

If the simulator misses a scrape, PromQL returns *nothing* for 5 min and
your alert fires "no data". `keep_last_value` carries the last known value
forward for up to N minutes, eliminating brittleness during planned restarts.

PromQL alternative: none. Closest is `last_over_time` but it changes shape.

---

## Bonus: `range_normalize` -- compare metrics on different scales

```promql
range_normalize(
    sum(rate(llm_tokens_total[5m])),
    sum(rate(llm_cost_usd_total[5m])),
    avg(DCGM_FI_DEV_POWER_USAGE)
)
```

Rescales each series to [0, 1] so you can overlay tokens/s, cost/s and GPU
power on one chart and spot correlations.

PromQL alternative: division by `max_over_time` per series, manually.

---

## Takeaway

These 6 functions cover ~80% of the awkward PromQL workarounds you write for
LLM workloads. They're the most concrete answer to "**why pick VM over
Prometheus** for LLM observability." Keep this page open during a customer
POC -- one demo per function = one billed differentiator.

---

## See also -- VM Differentiators dashboard

Open Grafana http://localhost:3000 -> folder *LLM Observability* ->
**VM Differentiators -- Demo & Training** -> **Row 1 -- MetricsQL functions PromQL doesn't have**.

Each panel in that row corresponds to one query above. Use it to demo the
feature live during a POC instead of typing into vmui.
