#!/usr/bin/env python3
"""LLM metrics simulator for the VictoriaMetrics observability lab.

Reference: Module 6.2 + Lab 1/3 of the training guide.

Generates realistic LLM workload metrics:
  - llm_requests_total / llm_errors_total (counters)
  - llm_request_duration_ms / llm_ttft_ms (histograms)
  - llm_tokens_total{type=input|output} / llm_cost_usd_total (counters)
  - rag_retrieval_score_avg (gauge, with optional drift injection)
  - rag_context_pressure_ratio (histogram)
  - rag_chunks_dropped_total (counter)
  - DCGM_FI_DEV_GPU_UTIL / DCGM_FI_DEV_POWER_USAGE / DCGM_FI_DEV_FB_USED / _FB_TOTAL (gauges)

Exposes /metrics on :9100 (override with --port).

Usage:
  python simulate_llm_metrics.py --rps 10 --models 3 --duration 300
  python simulate_llm_metrics.py --score-drift 0.5      # Lab 3: drop RAG quality
"""
import argparse
import math
import random
import signal
import sys
import threading
import time

from prometheus_client import (
    Counter,
    Gauge,
    Histogram,
    start_http_server,
)

# ---------------------------------------------------------------------------
# Metric definitions (mirror Module 6.2)
# ---------------------------------------------------------------------------

LLM_REQUESTS = Counter(
    'llm_requests_total', 'Total LLM requests',
    ['model', 'provider', 'pipeline_id', 'status'],
)
LLM_ERRORS = Counter(
    'llm_errors_total', 'Total LLM errors',
    ['model', 'provider', 'error_type', 'status_code'],
)
LLM_DURATION = Histogram(
    'llm_request_duration_ms', 'LLM request duration in ms',
    ['model', 'provider', 'pipeline_id'],
    buckets=[50, 100, 200, 500, 1000, 2000, 5000, 10000, 30000],
)
LLM_TTFT = Histogram(
    'llm_ttft_ms', 'Time to first token in ms',
    ['model', 'provider'],
    buckets=[50, 100, 200, 500, 1000, 2000, 5000],
)
LLM_TOKENS = Counter(
    'llm_tokens_total', 'Total tokens processed',
    ['model', 'provider', 'type'],   # type: input|output
)
LLM_COST = Counter(
    'llm_cost_usd_total', 'Total cost in USD',
    ['model', 'provider', 'tenant_id', 'use_case'],
)

RAG_RETRIEVAL_SCORE = Gauge(
    'rag_retrieval_score_avg', 'Average retrieval similarity score',
    ['index_id', 'pipeline_id', 'strategy'],
)
RAG_CONTEXT_PRESSURE = Histogram(
    'rag_context_pressure_ratio', 'Context window pressure ratio (0-1)',
    ['pipeline_id', 'model'],
    buckets=[0.1, 0.3, 0.5, 0.7, 0.8, 0.85, 0.9, 0.95, 1.0],
)
RAG_CHUNKS_DROPPED = Counter(
    'rag_chunks_dropped_total', 'Chunks dropped from retrieval',
    ['pipeline_id', 'reason'],
)

# GPU metrics — fake DCGM exporter so the Grafana panels light up in the lab
DCGM_GPU_UTIL = Gauge(
    'DCGM_FI_DEV_GPU_UTIL', 'GPU utilization (%)',
    ['gpu', 'UUID', 'pod', 'namespace', 'node'],
)
DCGM_POWER = Gauge(
    'DCGM_FI_DEV_POWER_USAGE', 'GPU power (W)',
    ['gpu', 'UUID', 'pod', 'namespace', 'node'],
)
DCGM_FB_USED = Gauge(
    'DCGM_FI_DEV_FB_USED', 'GPU framebuffer used (MiB)',
    ['gpu', 'UUID', 'pod', 'namespace', 'node'],
)
DCGM_FB_TOTAL = Gauge(
    'DCGM_FI_DEV_FB_TOTAL', 'GPU framebuffer total (MiB)',
    ['gpu', 'UUID', 'pod', 'namespace', 'node'],
)

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

MODELS = [
    # (model, provider, input_price_per_token, output_price_per_token)
    ('gpt-4o',            'openai',     5.0e-6,  15.0e-6),
    ('gpt-4o-mini',       'openai',     0.15e-6,  0.6e-6),
    ('claude-3-5-sonnet', 'anthropic',  3.0e-6,  15.0e-6),
    ('mistral-large',     'mistral',    4.0e-6,  12.0e-6),
    ('llama-3-70b',       'self-hosted', 0.0,     0.0),
]

PIPELINES = ['support-rag', 'search-rag', 'agent-tools', 'chat-direct']
INDEXES = ['kb-products', 'kb-faq', 'kb-policies']
TENANTS = ['acme', 'globex', 'initech', 'umbrella', 'wonka']
USE_CASES = ['chat', 'summarization', 'code-assist', 'rag-qa']

GPUS = [
    {'gpu': '0', 'UUID': 'GPU-aaaa', 'pod': 'vllm-0', 'namespace': 'llm', 'node': 'gpu-node-1'},
    {'gpu': '1', 'UUID': 'GPU-bbbb', 'pod': 'vllm-1', 'namespace': 'llm', 'node': 'gpu-node-1'},
    {'gpu': '0', 'UUID': 'GPU-cccc', 'pod': 'vllm-2', 'namespace': 'llm', 'node': 'gpu-node-2'},
]

# ---------------------------------------------------------------------------
# Simulator
# ---------------------------------------------------------------------------

stop_flag = threading.Event()


def simulate_request(active_models, score_drift_factor):
    model, provider, p_in, p_out = random.choice(active_models)
    pipeline = random.choice(PIPELINES)
    tenant = random.choice(TENANTS)
    use_case = random.choice(USE_CASES)

    # Latency profile depends loosely on model "size"
    base_latency = {
        'gpt-4o':            900,
        'gpt-4o-mini':       350,
        'claude-3-5-sonnet': 1100,
        'mistral-large':     800,
        'llama-3-70b':       1500,
    }.get(model, 800)
    duration_ms = max(20, random.gauss(base_latency, base_latency * 0.4))
    ttft_ms = max(20, random.gauss(base_latency * 0.3, base_latency * 0.15))

    # Token counts (input dominates in RAG)
    in_tok = max(10, int(random.gauss(800, 400)))
    out_tok = max(5, int(random.gauss(180, 100)))

    # Errors: 0.3% baseline, occasional bursts
    is_error = random.random() < 0.003
    status = 'error' if is_error else 'success'

    LLM_REQUESTS.labels(model=model, provider=provider,
                        pipeline_id=pipeline, status=status).inc()
    LLM_DURATION.labels(model=model, provider=provider,
                        pipeline_id=pipeline).observe(duration_ms)
    LLM_TTFT.labels(model=model, provider=provider).observe(ttft_ms)

    if is_error:
        LLM_ERRORS.labels(model=model, provider=provider,
                          error_type=random.choice(['timeout', 'rate_limit', 'upstream']),
                          status_code=random.choice(['429', '500', '503'])).inc()
        return

    LLM_TOKENS.labels(model=model, provider=provider, type='input').inc(in_tok)
    LLM_TOKENS.labels(model=model, provider=provider, type='output').inc(out_tok)
    cost = in_tok * p_in + out_tok * p_out
    if cost > 0:
        LLM_COST.labels(model=model, provider=provider,
                        tenant_id=tenant, use_case=use_case).inc(cost)

    # RAG side
    pressure = min(1.0, max(0.05, random.gauss(0.55, 0.2)))
    RAG_CONTEXT_PRESSURE.labels(pipeline_id=pipeline, model=model).observe(pressure)
    if random.random() < 0.05:
        RAG_CHUNKS_DROPPED.labels(pipeline_id=pipeline,
                                  reason=random.choice(['oversize', 'low-score'])).inc()


def update_gauges(t, score_drift_factor):
    """Update gauge-style metrics on a slow tick (every second)."""
    # RAG retrieval score: nominal ~0.82 with slow oscillation
    base = 0.82 + 0.05 * math.sin(t / 60.0)
    base *= score_drift_factor   # Lab 3: --score-drift 0.5 drops scores in half
    for idx in INDEXES:
        for pipe in PIPELINES:
            jitter = random.uniform(-0.03, 0.03)
            RAG_RETRIEVAL_SCORE.labels(
                index_id=idx, pipeline_id=pipe, strategy='hybrid'
            ).set(max(0.0, min(1.0, base + jitter)))

    # Fake DCGM metrics
    for gpu in GPUS:
        util = max(0.0, min(100.0, random.gauss(70, 15)))
        power = max(50.0, min(400.0, random.gauss(220, 40)))
        fb_total = 80 * 1024  # 80 GiB in MiB (A100-style)
        fb_used = fb_total * max(0.1, min(0.95, random.gauss(0.65, 0.1)))
        DCGM_GPU_UTIL.labels(**gpu).set(util)
        DCGM_POWER.labels(**gpu).set(power)
        DCGM_FB_USED.labels(**gpu).set(fb_used)
        DCGM_FB_TOTAL.labels(**gpu).set(fb_total)


def workload_thread(rps, active_models, score_drift_factor, duration):
    """Generate `rps` requests/s for `duration` seconds (0 = forever)."""
    start = time.monotonic()
    next_tick = start
    while not stop_flag.is_set():
        if duration and (time.monotonic() - start) > duration:
            stop_flag.set()
            break
        for _ in range(rps):
            simulate_request(active_models, score_drift_factor)
        next_tick += 1.0
        sleep = next_tick - time.monotonic()
        if sleep > 0:
            stop_flag.wait(sleep)


def gauge_thread(score_drift_factor):
    t0 = time.monotonic()
    while not stop_flag.is_set():
        update_gauges(time.monotonic() - t0, score_drift_factor)
        stop_flag.wait(1.0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rps', type=int, default=10,
                        help='Requests per second (default: 10)')
    parser.add_argument('--models', type=int, default=3,
                        help='Number of active models (1-5, default: 3)')
    parser.add_argument('--duration', type=int, default=0,
                        help='Stop after N seconds (0 = run forever)')
    parser.add_argument('--score-drift', type=float, default=1.0,
                        help='Multiplier on RAG retrieval scores. '
                             '0.5 -> halve scores to trigger RAGIndexDrift (Lab 3).')
    parser.add_argument('--port', type=int, default=9100,
                        help='Prometheus exposition port (default: 9100)')
    args = parser.parse_args()

    n = max(1, min(args.models, len(MODELS)))
    active_models = MODELS[:n]

    print(f'[simulator] starting on :{args.port}  rps={args.rps}  '
          f'models={[m[0] for m in active_models]}  drift={args.score_drift}',
          flush=True)
    start_http_server(args.port)

    signal.signal(signal.SIGTERM, lambda *_: stop_flag.set())
    signal.signal(signal.SIGINT, lambda *_: stop_flag.set())

    t1 = threading.Thread(target=workload_thread,
                          args=(args.rps, active_models, args.score_drift, args.duration),
                          daemon=True)
    t2 = threading.Thread(target=gauge_thread,
                          args=(args.score_drift,),
                          daemon=True)
    t1.start()
    t2.start()
    try:
        while not stop_flag.is_set():
            stop_flag.wait(1.0)
    finally:
        print('[simulator] shutting down', flush=True)


if __name__ == '__main__':
    main()
