# Demo loaders for the VM Differentiators dashboard

Each script creates the data conditions needed for the corresponding row of
[`VM Differentiators -- Demo & Training`](http://localhost:3000/d/vm-diff)
to actually demonstrate something visible. In idle conditions, MetricsQL's
power is invisible -- you need the right injection.

| Script | Row | Effect | Time to visible |
|---|---|---|---|
| `row1_metricsql.sh` | 1 -- MetricsQL exclusive | RAG drift + latency outlier on gpt-4o | 30 s |
| `row2_streamaggr.sh` | 2 -- Stream aggregation | Enables `--streamAggr.config` in vmagent | 60 s |
| `row3_otel.sh` | 3 -- OTel exp histograms | Verifies + bursts traffic to llm-app | 30 s |
| `row4_cardinality.sh` | 4 -- Cardinality | Pushes 5000 high-cardinality demo series | 5 s |
| `all.sh` | All 4 | Runs everything in the right order | 60 s |
| `clean.sh` | -- | Reverts everything | 30 s |

## Use from the Makefile

```bash
make demo-row1        # MetricsQL row
make demo-row2        # Stream aggregation row
make demo-row3        # OTel histograms row
make demo-row4        # Cardinality row
make demo-all         # All rows
make demo-clean       # Revert
```

## Use directly

```bash
bash scripts/demo/row1_metricsql.sh
bash scripts/demo/all.sh
bash scripts/demo/clean.sh
```

## Why we need this

The VM Differentiators dashboard demonstrates features that **only show
their value under specific conditions**:

- **outliers_iqr** needs at least one series whose value falls outside the
  IQR fence -- nothing to highlight in a healthy nominal regime.
- **share_le_over_time(... , 0.85)** stays at 0% if RAG quality never drops.
- **anomaly_score / z-score** needs deviation from baseline.
- **stream aggregation series** (`llm:cost_usd:agg1h`) only exist if
  `--streamAggr.config` is enabled.
- **OTel exponential histograms** only appear if llm-app is producing data.
- **Cardinality jump panels** are flat unless you inject high-cardinality data.

These scripts inject exactly the right amount of "demo signal" so each row
visualizes its feature within 30-60 seconds.
