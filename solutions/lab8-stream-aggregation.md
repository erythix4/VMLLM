# Lab 8 -- vmagent stream aggregation (VM-only ingestion-time rollup)
*Estimated 25 min · level: advanced*

## Why this matters for LLM workloads

`llm_cost_usd_total{model, provider, tenant_id, use_case}` with 50 tenants ×
10 models × 4 use_cases = **2 000 series** at full cardinality. Kept for
3 years (Module 11), that's a measurable storage bill.

You don't actually query cost at the use_case level for the 3-year tier --
you query it for monthly invoicing. So pre-aggregate at ingestion: drop
`use_case`, roll over 1-hour windows, write a much smaller series under a
new name.

VM does this **at the vmagent layer, before the data lands**. No
recomputation, no CPU on the read path, and the original series can have a
short retention while the aggregated series carries the long one.

Prometheus can't do this. Mimir/Cortex have recording rules but they run
post-write. vmagent stream aggregation is **the** unique selling point for
high-retention cost metrics.

## What's wired up

The `streamAggr.yaml` at the lab root is mounted into vmagent via the flag
`--streamAggr.config=/etc/streamAggr.yaml` (uncomment in `docker-compose.yml`
to activate -- left commented by default so the dashboard panels keep working
on the raw series).

## Walkthrough

1. Enable the flag and restart vmagent:
   ```bash
   sed -i "s|# - '--streamAggr|- '--streamAggr|" docker-compose.yml
   docker compose restart vmagent
   ```

2. After 1 minute, query the aggregated series in vmui:
   ```promql
   llm:cost_usd:agg1h
   llm:requests:agg1m
   llm:tokens:agg1m
   ```

3. Compare cardinality before vs after:
   ```bash
   # Raw series cardinality
   curl -s 'http://localhost:8428/api/v1/series/count?match[]=llm_cost_usd_total'

   # Aggregated cardinality
   curl -s 'http://localhost:8428/api/v1/series/count?match[]=llm:cost_usd:agg1h'
   ```

4. The `dedup_interval` (vm flag `--dedup.minScrapeInterval=1m`) makes
   ingestion idempotent -- run vmagent in HA pairs without double-counting.

## Production retention strategy

```
llm_cost_usd_total       -> 7-day retention   (full debug detail)
llm:cost_usd:agg1h       -> 3-year retention  (audit + invoicing)
```

Configure with two VictoriaMetrics tiers via vmauth or by routing different
metrics to different VM instances based on label `__name__ =~ "llm:.*"`.

---

## See also -- VM Differentiators dashboard

Open Grafana http://localhost:3000 -> folder *LLM Observability* ->
**VM Differentiators -- Demo & Training** -> **Row 2 -- vmagent stream aggregation**.

Each panel in that row corresponds to one query above. Use it to demo the
feature live during a POC instead of typing into vmui.
