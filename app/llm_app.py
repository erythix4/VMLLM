"""FastAPI demo app -- LLM + RAG instrumented with OpenTelemetry SDK.

Reference: Module 6.1 (OTLP via OTel SDK) and Module 7 (RAG quality metrics).

Pushes both METRICS and TRACES to the OTel Collector via OTLP gRPC :4317.
Traces carry gen_ai.* and rag.* attributes so the spanmetrics CONNECTOR
in the Collector derives RED metrics into VictoriaMetrics automatically.

Endpoints:
  POST /chat       -- single LLM call (fake completion, real metrics)
  POST /rag        -- retrieve + LLM call (full RAG pipeline trace)
  GET  /health
"""
import asyncio
import os
import random
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI
from pydantic import BaseModel

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")
SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "llm-demo-app")

# ---------------------------------------------------------------------------
# OTel setup
# ---------------------------------------------------------------------------

resource = Resource.create({"service.name": SERVICE_NAME})

# Traces -> OTLP -> spanmetrics connector -> VM
trace_provider = TracerProvider(resource=resource)
trace_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT, insecure=True))
)
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer(__name__)

# Metrics -> OTLP -> remoteWrite VM
reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint=OTLP_ENDPOINT, insecure=True),
    export_interval_millis=5000,
)
metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))
meter = metrics.get_meter(__name__)

# OTLP-style metrics (will land in VM with the same name)
m_requests = meter.create_counter(
    "llm_requests_total", description="Total LLM requests"
)
m_tokens = meter.create_counter(
    "llm_tokens_total", description="Tokens processed (input/output)"
)
m_cost = meter.create_counter(
    "llm_cost_usd_total", description="LLM cost in USD"
)
m_duration = meter.create_histogram(
    "llm_request_duration_ms", description="Request duration (ms)", unit="ms"
)
m_ttft = meter.create_histogram(
    "llm_ttft_ms", description="Time to first token (ms)", unit="ms"
)
m_score = meter.create_histogram(
    "rag_retrieval_score_avg", description="Mean retrieval similarity score"
)

# ---------------------------------------------------------------------------
# Fake LLM + RAG (no external API key needed)
# ---------------------------------------------------------------------------

PRICES = {
    "gpt-4o":            {"in": 5.0e-6,  "out": 15.0e-6},
    "claude-3-5-sonnet": {"in": 3.0e-6,  "out": 15.0e-6},
    "mistral-large":     {"in": 4.0e-6,  "out": 12.0e-6},
}

class ChatReq(BaseModel):
    model: str = "gpt-4o"
    provider: str = "openai"
    pipeline_id: str = "chat-direct"
    tenant_id: str = "demo"
    user_message: str = "Hello"

class RagReq(ChatReq):
    pipeline_id: str = "support-rag"
    index_id: str = "kb-products"


async def fake_completion(model: str):
    """Simulate an LLM call -- realistic latency and token counts."""
    base = {"gpt-4o": 900, "claude-3-5-sonnet": 1100, "mistral-large": 800}.get(model, 800)
    ttft = max(20.0, random.gauss(base * 0.3, base * 0.15))
    total = max(ttft + 20, random.gauss(base, base * 0.3))
    await asyncio.sleep(total / 1000.0)
    in_tok = max(10, int(random.gauss(800, 400)))
    out_tok = max(5, int(random.gauss(180, 100)))
    return {"ttft_ms": ttft, "duration_ms": total, "in_tok": in_tok, "out_tok": out_tok}


async def fake_retrieval(index_id: str):
    """Simulate vector retrieval -- returns a similarity score in [0, 1]."""
    await asyncio.sleep(random.uniform(0.02, 0.08))
    return max(0.0, min(1.0, random.gauss(0.82, 0.05)))


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(_):
    print(f"[llm-app] OTLP -> {OTLP_ENDPOINT}", flush=True)
    yield

app = FastAPI(title="LLM Demo App", lifespan=lifespan)


@app.get("/health")
async def health():
    return {"ok": True}


@app.post("/chat")
async def chat(req: ChatReq):
    with tracer.start_as_current_span("llm.chat") as span:
        span.set_attribute("gen_ai.system", req.provider)
        span.set_attribute("gen_ai.request.model", req.model)
        span.set_attribute("rag.tenant.id", req.tenant_id)
        span.set_attribute("rag.pipeline.id", req.pipeline_id)

        t0 = time.perf_counter()
        result = await fake_completion(req.model)

        labels = {"model": req.model, "provider": req.provider,
                  "pipeline_id": req.pipeline_id, "status": "success"}
        m_requests.add(1, labels)
        m_duration.record(result["duration_ms"], labels)
        m_ttft.record(result["ttft_ms"], {"model": req.model, "provider": req.provider})

        m_tokens.add(result["in_tok"],  {"model": req.model, "provider": req.provider, "type": "input"})
        m_tokens.add(result["out_tok"], {"model": req.model, "provider": req.provider, "type": "output"})

        if req.model in PRICES:
            p = PRICES[req.model]
            cost = result["in_tok"] * p["in"] + result["out_tok"] * p["out"]
            m_cost.add(cost, {"model": req.model, "provider": req.provider,
                              "tenant_id": req.tenant_id, "use_case": "chat"})
        return {"ok": True, **result}


@app.post("/rag")
async def rag(req: RagReq):
    with tracer.start_as_current_span("rag.pipeline") as parent:
        parent.set_attribute("rag.pipeline.id", req.pipeline_id)
        parent.set_attribute("rag.index.id", req.index_id)
        parent.set_attribute("rag.tenant.id", req.tenant_id)

        with tracer.start_as_current_span("rag.retrieval") as ret:
            ret.set_attribute("rag.index.id", req.index_id)
            score = await fake_retrieval(req.index_id)
            ret.set_attribute("rag.retrieval.score", score)
            m_score.record(score, {"index_id": req.index_id,
                                   "pipeline_id": req.pipeline_id,
                                   "strategy": "hybrid"})

        with tracer.start_as_current_span("llm.chat") as gen:
            gen.set_attribute("gen_ai.system", req.provider)
            gen.set_attribute("gen_ai.request.model", req.model)
            result = await fake_completion(req.model)

            labels = {"model": req.model, "provider": req.provider,
                      "pipeline_id": req.pipeline_id, "status": "success"}
            m_requests.add(1, labels)
            m_duration.record(result["duration_ms"], labels)
            m_ttft.record(result["ttft_ms"], {"model": req.model, "provider": req.provider})
            m_tokens.add(result["in_tok"],  {"model": req.model, "provider": req.provider, "type": "input"})
            m_tokens.add(result["out_tok"], {"model": req.model, "provider": req.provider, "type": "output"})
            if req.model in PRICES:
                p = PRICES[req.model]
                cost = result["in_tok"] * p["in"] + result["out_tok"] * p["out"]
                m_cost.add(cost, {"model": req.model, "provider": req.provider,
                                  "tenant_id": req.tenant_id, "use_case": "rag-qa"})

        return {"ok": True, "retrieval_score": score, **result}
