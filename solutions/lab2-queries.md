# Lab 2 — Solution queries

## 1. Total cost by model over the last 24 hours
```promql
sum by (model, provider) (
    increase(llm_cost_usd_total[24h])
)
```
Tip: stack-area panel with `currencyUSD` unit.

## 2. TTFT P95 by provider (histogram_quantile)
```promql
histogram_quantile(0.95,
    sum by (le, provider) (
        rate(llm_ttft_ms_bucket[5m])
    )
)
```
Tip: time series panel, unit `ms`, threshold red at 2000.

## 3. RAG retrieval score anomaly (anomaly_score, MetricsQL-only)
```promql
anomaly_score(
    avg by (index_id) (rag_retrieval_score_avg),
    "7d"
)
```
Returns ~0 in nominal regime, > 1 on significant deviation vs the 7-day
baseline. Set the threshold line at 1.0 in Grafana.

## 4. Top 5 tenants by cost (last 24h)
```promql
topk(5,
    sum by (tenant_id) (
        increase(llm_cost_usd_total[24h])
    )
)
```
Tip: instant query in a *Table* panel.

## 5. GPU efficiency — tokens per watt
```promql
sum by (model) (
    rate(llm_tokens_total{type="output"}[5m])
)
  /
clamp_min(
    avg by (model) (DCGM_FI_DEV_POWER_USAGE), 1
)
```
The `clamp_min(..., 1)` guards against divide-by-zero when GPU exporters are
temporarily unavailable. Higher = more energy-efficient.
