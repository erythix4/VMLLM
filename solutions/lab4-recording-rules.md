# Lab 4 — Recording rules: measured speed-up

## Why pre-aggregate?

`histogram_quantile(0.99, sum by (le, model, pipeline_id) (rate(llm_request_duration_ms_bucket[5m])))`
must, at every dashboard refresh:

1. Read every `*_bucket` series matching the selector,
2. Compute `rate()` over the last 5 minutes,
3. Sum across the `le` dimension,
4. Solve the histogram quantile.

On a 5-million active series production VictoriaMetrics, this can take 1-3 s
per panel and dominates the Grafana wall-clock. Recording rules pre-compute
the result every minute and store it as a regular gauge series.

## Method

```bash
# Direct query (raw)
time curl -sG 'http://localhost:8428/api/v1/query' \
    --data-urlencode 'query=histogram_quantile(0.99, sum by (le, model, pipeline_id) (rate(llm_request_duration_ms_bucket[5m])))' \
    > /dev/null

# Pre-aggregated (recording rule)
time curl -sG 'http://localhost:8428/api/v1/query' \
    --data-urlencode 'query=llm:request_duration_ms:p99_5m' \
    > /dev/null
```

Run each ~10 times and compare medians.

## Indicative results

| Scale (active series) | Raw query | Recording rule | Speed-up |
|-----------------------|-----------|----------------|----------|
| Lab simulator (~200)  |  ~10 ms   |   ~3 ms        |   ~3×    |
| Mid-size (500 k)      |   ~250 ms |   ~8 ms        |   ~30×   |
| Production (5 M)      |   ~2 s    |   ~15 ms       |   ~130×  |

Speed-up grows with cardinality. The lab cardinality is intentionally tiny so
the absolute numbers are small, but the trend is the same.

## Where to use recording rules

- **Always** for panels that refresh every 30 s (status pages, NOC TVs).
- For alert expressions queried every minute by vmalert: cuts evaluation
  latency and reduces vmalert CPU.
- Anywhere a query takes > 100 ms — including any cost rollup over 24 h.

## Trade-offs to watch

- Each rule emits new series → cardinality grows. Keep the `by()` dimensions
  tight (drop labels you do not query).
- Backfill is not retroactive: a brand new rule starts emitting data only from
  now on.
- Naming convention `<domain>:<metric>:<aggregation><window>` keeps
  recording rules easy to find. Example: `llm:cost_usd:rate24h`.
