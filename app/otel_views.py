"""Custom views: switch llm_*_ms histograms to OTel exponential aggregation.

Reference: https://opentelemetry.io/docs/specs/otel/metrics/data-model/#exponentialhistogram
VictoriaMetrics stores OTel exponential histograms natively
(see https://docs.victoriametrics.com/keyconcepts/#histogram).

Compared to explicit-bucket histograms:
  + sub-millisecond resolution at low latencies (TTFT)
  + no need to pre-pick buckets that fit your distribution
  + smaller storage footprint at equivalent precision
  - PromQL `histogram_quantile()` does not work directly; use VM's
    `histogram_quantile()` which understands both formats.
"""
from opentelemetry.sdk.metrics.view import View, ExponentialBucketHistogramAggregation

LLM_HISTOGRAM_VIEWS = [
    View(
        instrument_name="llm_request_duration_ms",
        aggregation=ExponentialBucketHistogramAggregation(max_size=160, max_scale=20),
    ),
    View(
        instrument_name="llm_ttft_ms",
        aggregation=ExponentialBucketHistogramAggregation(max_size=160, max_scale=20),
    ),
]
