# Architecture -- VictoriaMetrics LLM Observability Lab

> Reference document for the lab built around the Erythix premium training
> *"VictoriaMetrics as an LLM Observability Backend"*. Describes every
> component, how data flows between them, what choices were made and why,
> and how the lab differs from a production deployment.

---

## 1. Executive summary

LLM workloads stress observability backends in ways HTTP-microservice
workloads do not: token histograms with 100x range, USD cost metrics that
need 3-year retention, multi-tenant cardinality (model x provider x tenant
x pipeline), and ingestion bursts during batch completions.

This lab demonstrates a sovereign, air-gap-capable stack built on
**VictoriaMetrics + OpenTelemetry** that handles those constraints out of
the box. It implements two ingestion paths (Prometheus client and OTLP), a
production alert ruleset, a backup-and-restore drill, and a Cluster-mode
variant -- all in one `docker compose up`.

The core thesis: **VictoriaMetrics is a strictly better fit than plain
Prometheus for LLM observability**, and the lab proves it with three
dashboards and ten labs. See `solutions/lab6-metricsql-exclusive.md` for
the most direct technical defense.

---

## 2. Context and design goals

| Goal | Why it matters for LLM workloads | How the lab meets it |
|---|---|---|
| **High cardinality stable** | model x provider x tenant x pipeline = thousands of series | VM stays linear up to 10M+ active series (Prom degrades > 500k) |
| **Long retention** | Cost audit (GDPR/NIS2): 3-year minimum | `--retentionPeriod=12` in lab; recommend `=24m` for cost in prod |
| **Cheap storage** | Token + cost data accumulate fast | VM ~10:1 compression, vs Prom ~4:1 |
| **OTel native** | Modern LLM SDKs emit OTLP, not Prometheus exposition | Direct OTLP ingestion + spanmetrics connector |
| **Single binary** | Easy POC, easy first-prod | VM Single mode = 1 container in lab |
| **Cluster-ready** | Above 500k series or HA SLA | VM Cluster mode 1:1 in `docker-compose.cluster.yml` |
| **Air-gap deployable** | Sovereign compliance / regulated industries | All components OSS, no phone-home, vmbackup -> S3-compatible storage |
| **MetricsQL > PromQL** | Anomaly detection, IQR outliers, share_le_over_time | Lab 6 demonstrates 6 functions PromQL doesn't have |

---

## 3. High-level architecture (Single mode)

```
                       +--------------------+        +-----------------+
                       | LLM applications   |        | GPU node (DCGM) |
                       | (FastAPI, vLLM,    |        | exporter        |
                       |  Ollama, LiteLLM)  |        +-----------------+
                       +--------+-----------+                 |
                                |                             |
                       OTLP gRPC (4317)               Prometheus scrape
                                |                             |
                                v                             |
                       +--------------------+                 |
                       | OTel Collector     |                 |
                       |  - otlp receiver   |                 |
                       |  - prometheus      |                 |
                       |    receiver        |<----------------+
                       |  - batch processor |
                       |  - spanmetrics     |
                       |    connector       |
                       |  - prom rwexporter |
                       +--------+-----------+
                                |
                                | remote_write
                                |
+------------+    scrape   +----v---------------------+
| llm-       |<------------| vmagent                  |
| simulator  |             |  - promscrape            |
| (:9100)    |             |  - streamAggr (optional) |
+------------+             +----+---------------------+
                                |
                                | remote_write
                                v
                       +--------------------+      +------------------+
                       | VictoriaMetrics    |<-----| vmalert          |
                       | Single (8428)      |      |  alert + record  |
                       |  - TSDB            |      |  rules eval      |
                       |  - MetricsQL       |      +--------+---------+
                       |  - vmui            |               |
                       +-+--------+---------+               |
                         |        ^                         |
              datasource |        | snapshot                v
                         v        |                +-----------------+
                  +-------------+ |                | Alertmanager    |
                  |   Grafana   | |                |  routing        |
                  |  (3000)     | |                |  Slack / PD     |
                  |  3 dashs    | |                +-----------------+
                  +-------------+ |
                                  |
                                  v
                          +---------------+
                          | vmbackup      |
                          | -> MinIO (S3) |  Lab 5 only
                          +---------------+
```

**Three ingestion paths run side by side** in the lab so trainees can
compare patterns:

1. **Path A (Prometheus client)** -- `llm-simulator` -> exposition format
   on `/metrics` -> vmagent scrape -> remote_write -> VM.
   Distinguishing labels: `job=llm-simulator`, `instance=llm-simulator:9100`.
2. **Path B (OTLP metric push)** -- `llm-app` (OTel SDK histogram) ->
   OTLP gRPC -> OTel collector -> remote_write -> VM. The exporter
   appends the unit suffix, so the metric name becomes
   `llm_request_duration_ms_milliseconds`. Distinguishing label:
   `service_name=llm-demo-app`.
3. **Path C (OTLP traces -> spanmetrics)** -- `llm-app` traces ->
   spanmetrics CONNECTOR in OTel collector -> remote_write -> VM. The
   connector emits `duration_milliseconds_*` and propagates dimensions
   `gen_ai_request_model`, `gen_ai_system`, `rag_index_id`,
   `rag_pipeline_id`, `rag_tenant_id`.

All three paths land in the same VM TSDB. The OTel collector also
scrapes `victoriametrics`, `vmagent`, `vmalert`, and `otel-collector`
itself for self-monitoring (in addition to vmagent doing the same).

---

## 4. Component reference

### 4.1 VictoriaMetrics (Single)

| Aspect | Value |
|---|---|
| Container | `vm-llm` |
| Image | `victoriametrics/victoria-metrics:v1.99.0` |
| Listen | `:8428` (HTTP) |
| Storage | `vm-data` named volume, retention 12 months |
| Key flags | `--retentionPeriod=12 --search.maxQueryLen=16384 --search.maxSamplesPerQuery=1000000000 --memory.allowedPercent=60 --loggerFormat=json` |
| Self-metrics | Available at `:8428/metrics`, scraped by vmagent |
| MetricsQL | Superset of PromQL; see `solutions/lab6-metricsql-exclusive.md` |
| vmui | `:8428/vmui` -- query playground, cardinality drill-down |

**Why Single in the lab** -- one binary, one volume, ~600 MB RAM under
synthetic load. Migration to Cluster (Section 9) is non-destructive.

### 4.2 OpenTelemetry Collector

| Aspect | Value |
|---|---|
| Container | `otel-collector-llm` |
| Image | `otel/opentelemetry-collector-contrib:0.99.0` |
| Listen | `:4317` (gRPC), `:4318` (HTTP) |
| Receivers | `otlp` + `prometheus` (scrapes simulator) |
| Connectors | `spanmetrics` -- derives RED metrics from RAG traces |
| Exporter | `prometheusremotewrite` -> VM |

**Important** -- since OTel Collector 0.96, `spanmetrics` is a **connector**
(not a processor). The training guide example targets older versions; the
lab uses the connector form so 0.99.0 starts cleanly.

The collector is the single point where:
- OTLP-emitted attributes from `llm-app` (`gen_ai.*`, `rag.*`) become
  Prometheus labels via `resource_to_telemetry_conversion: enabled`.
- Trace spans become metrics via the spanmetrics connector.
- All metrics get batched (5s, 512 samples) before remote_write.

### 4.3 vmagent

| Aspect | Value |
|---|---|
| Container | `vmagent-llm` |
| Image | `victoriametrics/vmagent:v1.99.0` |
| Function | Prometheus-style scraping + remote_write to VM |
| Scrape targets | `llm-simulator`, `victoriametrics`, `vmalert` (lab); DCGM/vLLM/Ollama/LiteLLM commented (prod) |
| Stream aggregation | `--streamAggr.config=/etc/streamAggr.yaml` (optional, Lab 8) |

**Stream aggregation** is the VM-only feature that pre-rolls
`llm_cost_usd_total` to 1-hour windows AT INGESTION (1-min in the lab for
visibility). Cardinality drops ~10x before data lands.

**Important flag name** -- in vmagent v1.99 the flag is
`-remoteWrite.streamAggr.config=...` (per remote_write config),
**not** `-streamAggr.config` which doesn't exist. A wrong flag name
makes vmagent crashloop with `flag provided but not defined`.

### 4.4 vmalert

| Aspect | Value |
|---|---|
| Container | `vmalert-llm` |
| Listen | `:8880` (UI + API) |
| Datasource | VM (read) |
| Remote write | VM (for recording-rule output) |
| Notifier | Alertmanager `:9093` |
| Eval interval | 30s |
| Rules loaded | 7 alerts (`llm-quality.yml`) + 8 recording rules (`recording-rules.yml`) |

### 4.5 Alertmanager

| Aspect | Value |
|---|---|
| Container | `alertmanager-llm` |
| Image | `prom/alertmanager:v0.27.0` |
| Listen | `:9093` |
| Routing | `severity=critical` -> pagerduty; `team=ai-platform` -> slack-ai-platform; `team=billing` -> slack-billing; default -> webhook |
| Inhibit | critical inhibits warning when same `alertname/model/pipeline_id` |

In the lab, all receivers point to `webhook.site` URLs so notifications
can be observed without configuring real Slack/PD. Replace with real
endpoints in `alertmanager.yml` for a real demo.

### 4.6 Grafana

| Aspect | Value |
|---|---|
| Container | `grafana-llm` |
| Image | `grafana/grafana:10.4.0` |
| Listen | `:3000` (admin/admin) |
| Plugins | `victoriametrics-metrics-datasource` (auto-installed) |
| Auth | Anonymous viewer enabled (lab convenience) |
| Default home | `lab-home` dashboard via `GF_USERS_HOME_DASHBOARD_UID` |
| Provisioning | Datasources + 4 dashboards auto-loaded |

**The 4 dashboards**

| Dashboard | UID | Audience |
|---|---|---|
| Home -- VictoriaMetrics LLM Lab | `lab-home` | Everyone (landing page) |
| LLM Observability -- Production | `llm-prod` | Business / LLM Ops |
| VM Ops -- Cardinality & Performance | `vm-ops` | SRE / Platform |
| VM Differentiators -- Demo & Training | `vm-diff` | POC / sales |

### 4.7 llm-simulator

| Aspect | Value |
|---|---|
| Container | `llm-simulator` |
| Build | `Dockerfile.simulator` (Python 3.12 + prometheus-client) |
| Listen | `:9100/metrics` |
| Workload | 10 rps default, 3 active models, ~8% RAG drift sine wave |
| Flags | `--rps`, `--models`, `--duration`, `--score-drift`, `--port` |

Emits all 10 LLM metrics from Module 5 of the guide using explicit-bucket
histograms. Used by Lab 1, 3 (drift injection), and the `verify_panels.sh`
end-to-end test.

### 4.8 llm-app + llm-traffic (OTel path)

| Aspect | Value |
|---|---|
| Containers | `llm-app` (FastAPI) + `llm-traffic` (continuous client) |
| Build | `app/Dockerfile`, `app/Dockerfile.traffic` |
| llm-app endpoints | `POST /chat`, `POST /rag`, `GET /health` (port 8001) |
| Instrumentation | OpenTelemetry SDK -- traces + metrics, **exponential histograms** |
| Resource attributes | `service.name=llm-demo-app` (becomes `service_name` label) |

llm-app is the Module 6.1 reference -- "OTLP via OTel SDK" approach. It
demonstrates that the same metric names (`llm_request_duration_ms`, etc.)
can land in VM via either the Prometheus path OR the OTel path, side by
side.

The exponential histogram view (`app/otel_views.py`) is **parked** for
now -- in OTel SDK Python 1.25, `ExponentialBucketHistogramAggregation`
is experimental and the `PeriodicExportingMetricReader` silently fails
to flush histograms when this aggregation is set. The lab uses default
explicit-bucket aggregation, which produces standard `_bucket`/`_sum`/
`_count` series. The view config remains in the repo for the day the
SDK API stabilizes.

---

## 5. Data flows

### 5.1 Metric ingestion (path A -- Prometheus)

```
llm-simulator              vmagent                       VictoriaMetrics
     |                        |                                 |
     | 1. expose /metrics      |                                |
     |    (Prom exposition fmt)|                                |
     |                        |                                 |
     |    GET /metrics every  |                                 |
     |   <-------------------- 5s                               |
     |                        |                                 |
     |                        | 2. relabel (cluster, env)       |
     |                        | 3. (optional) streamAggr        |
     |                        |    -> emit llm:cost_usd:agg1h   |
     |                        |                                 |
     |                        | 4. remote_write batched         |
     |                        | -------------------------> 5. parse + index
     |                        |                                 + compress (10:1)
     |                        |                                 + persist to disk
```

### 5.2 Metric ingestion (path B -- OTLP)

```
llm-app             OTel Collector                  VictoriaMetrics
   |                      |                              |
   | 1. OTLP gRPC          |                             |
   |    payload (metrics  |                              |
   |    + traces)         |                              |
   | -------------------> | 2. otlp receiver decodes     |
   |                      | 3. resource_to_telemetry     |
   |                      |    -> labels gen_ai_system,  |
   |                      |       service_name, etc.     |
   |                      | 4. batch (5s, 512 samples)   |
   |                      | 5. prometheusremotewrite     |
   |                      | --------------------------> 6. same parse + index
   |                      |                                + dedup if path A
   |                      |                                  produced same series
   |                      |                                  identical sample
```

Spanmetrics path (traces only):
```
llm-app traces -> spanmetrics connector -> RED metrics
                                        -> remote_write to VM
                                        -> series like
                                           traces_span_metrics_*
                                           with attributes from spans
```

### 5.3 Query path (Grafana panel render)

```
Grafana panel             VM datasource plugin            VictoriaMetrics
     |                            |                              |
     | 1. user opens dashboard    |                              |
     | 2. resolve $model variable |                              |
     | -- label_values(...) -->   |                              |
     |                            | -- /api/v1/label/.../values  |
     |                            | -- query expr w/ time range  |
     |                            | --------------------------> 3. parse MetricsQL
     |                            |                              4. fetch series
     |                            |                              5. apply funcs
     | <- panel data renders ---- | <-- result vector            6. (cache result)
     |                            |                              |
```

### 5.4 Alert path

```
Time -> 30s tick
   |
vmalert evaluates each rule:
   - load expr from llm-quality.yml
   - query VM via /api/v1/query
   - check threshold + duration (`for:`)
   - if firing for >= for_time: emit alert to AM
   - if recording rule: write result back via remote_write
                        |
                        v
              VictoriaMetrics
                  (rule output is just another metric:
                   llm:request_duration_ms:p99_5m, etc.)

Alert reaches Alertmanager:
   - group by (alertname, model, pipeline_id)
   - apply route matchers
       severity=critical -> pagerduty receiver
       team=ai-platform  -> slack-ai-platform
       team=billing      -> slack-billing
       default           -> webhook
   - apply inhibit rules (critical mutes warning of same group)
   - dedup + group_wait (30s)
   - dispatch -> webhook URL
```

### 5.5 Backup path (Lab 5)

```
                         every 5 min
                              |
         +--------------------+
         | vmbackup runner    |
         |  1. POST /snapshot/create on VM
         |     -> snapshot ID
         |  2. vmbackup-prod
         |       -snapshotName=ID
         |       -dst=s3://vm-backups/auto
         |       -customS3Endpoint=minio:9000
         |  3. POST /snapshot/delete?snapshot=ID
         +--------------------+
                              |
                              v
              MinIO bucket vm-backups/auto/
                  parts/   (incremental)
                  metadata/

   Restore:  vmrestore -src=s3://... -storageDataPath=...
              then docker compose restart victoriametrics
```

---

## 6. Cardinality and metric taxonomy

### 6.1 The 4 dimensions of LLM observability

```
+-------------+   +-------------+   +-------------+   +-------------+
| Quality     |   | Performance |   | Cost        |   | Infra       |
| (RAG)       |   | (Latency)   |   | (USD/Token) |   | (GPU)       |
+-------------+   +-------------+   +-------------+   +-------------+
       |                |                  |                |
       v                v                  v                v
 rag_retrieval_   llm_request_      llm_cost_usd_     DCGM_FI_DEV_*
   score_avg       duration_ms        total
 rag_context_    llm_ttft_ms       llm_tokens_total  vllm:*_running
   pressure_*    llm_errors_total
 rag_chunks_
   dropped_total
```

### 6.2 Recommended cardinality budget

| Metric | Cardinality budget | Why |
|---|---|---|
| `llm_requests_total` | model x provider x pipeline x status = ~100 | Always-on counter, frequent rate() |
| `llm_request_duration_ms_*` | + `le` x ~10 = ~1000 | Histograms have a multiplier |
| `llm_cost_usd_total` | model x provider x tenant x use_case = ~10,000 in prod | Necessary for billing -- accept the cost |
| `rag_retrieval_score_avg` | index_id x pipeline_id x strategy = ~50 | Low write rate (sampled), high read rate |
| `DCGM_FI_DEV_*` | gpu x UUID x pod x namespace x node = ~1000 | Bound by physical fleet |

### 6.3 Anti-patterns

Never label with: `trace_id`, `request_id`, `session_id`, `user_id`, raw
prompt content. Each unique value adds a series. A single rotating
trace_id field can blow cardinality past 10M in days.

Restrict `tenant_id` to **cost metrics only**. Don't let it propagate to
latency or token metrics -- you don't query latency-by-tenant in
practice, but you'd pay the cardinality.

Lab 7 (`make lab7-explode`) demonstrates this anti-pattern injection +
remediation.

---

## 7. Storage and retention

### 7.1 Tier strategy (production recommendation)

| Tier | Metrics | Retention | Storage rate (rough) |
|---|---|---|---|
| Hot (live ops) | `llm_request_duration_ms_*`, `llm_errors_total`, GPU | 30 days | 100% raw |
| Warm (trending) | `llm_tokens_total`, `rag_*` | 6 months | 30% (downsampled in Enterprise) |
| Cold (audit) | `llm_cost_usd_total` (rolled to `llm:cost_usd:agg1h`) | 3 years | 10% (post stream-agg) |

In the lab everything sits on a single `--retentionPeriod=12` (12 months),
which is enough to demonstrate the patterns but not enough for real cost
audit.

### 7.2 Stream aggregation as a tier-shifting tool

The `streamAggr.yaml` config drops `use_case` and rolls to 1h windows BEFORE
the data hits VM disk. The new metric `llm:cost_usd:agg1h` carries 10x less
cardinality than `llm_cost_usd_total`. In production:

```
llm_cost_usd_total       -> retention 7d  (debug)
llm:cost_usd:agg1h       -> retention 36m (audit, GDPR)
```

This kind of "two retentions for the same metric" is impossible in plain
Prometheus and is the single biggest reason to choose VM for LLM cost
data.

---

## 8. Security model

### 8.1 Authentication (Lab 5 -- vmauth)

Native VM has no auth. The lab introduces vmauth as a reverse proxy with
3 roles (Module 12.1):

| Role | Allowed paths | Used by |
|---|---|---|
| `grafana` | `/api/v1/query`, `/query_range`, `/labels`, `/series` | Grafana datasource |
| `otel-collector` | `/api/v1/write`, `/opentelemetry/api/v1/push` | OTel collector remote_write |
| `admin` | everything | ops humans |

In production, terminate TLS in front of vmauth (Nginx, Caddy, ingress
controller).

### 8.2 Network isolation (production guidance, not in lab)

```
NetworkPolicy: only otel-collector can write to vmauth-write-port
NetworkPolicy: only grafana can read from vmauth-read-port
NetworkPolicy: vmagent can scrape :8428/metrics from victoriametrics directly
```

In Kubernetes, this maps to NetworkPolicies + Services with appropriate
labels. In the lab Docker Compose network, all containers are on the
same default bridge.

### 8.3 PII / compliance posture

- **No PII in metric labels** -- never put raw prompts, user emails, or
  full names in labels. Use opaque IDs only.
- **Cost audit retention** -- 36 months for `llm_cost_usd_total` (or its
  aggregated form) per typical NIS2 / contractual SLA.
- **Encryption in transit** -- production: TLS in front of vmauth. Lab:
  unencrypted (localhost only).
- **Multi-tenant isolation** -- Lab uses single VM instance with
  tenant_id labels. Production with hard isolation requirement: use VM
  Cluster `accountID/projectID` URL paths.

---

## 9. Scalability -- Single vs Cluster

### 9.1 Decision matrix

| Criteria | Single | Cluster |
|---|---|---|
| Active series | < 1M | unlimited |
| Write rate | < 500 req/s | > 500 req/s |
| HA SLA | not native | replicas per component |
| LLM models in prod | 1-10 | > 10 or > 50 tenants |
| Containers needed | 1 | 4 (1 vminsert + 2 vmstorage + 1 vmselect) |
| Per-tier retention | identical | configurable |
| Ops complexity | very low | moderate |
| RAM | 1-4 GB | 4 GB+ per component |
| License | OSS Apache 2.0 | OSS Apache 2.0 |

### 9.2 When to migrate

```
IF  active_series > 500_000 
 OR P99 write latency > 50ms
 OR HA SLA required
THEN migrate Single -> Cluster
```

### 9.3 Migration procedure (lossless)

1. Start Cluster alongside Single.
2. Reconfigure vmagent: dual remote_write to both Single + Cluster.
3. Wait `--retentionPeriod` of overlap (or use vmctl for backfill).
4. Cut Grafana datasource to Cluster.
5. Stop Single.

In the lab: `make down && make cluster-up` (no migration -- just cold
swap; the lab is stateless enough that data loss is acceptable).

---

## 10. Air-gap deployment

The full stack (including Lab 5 overlay) has zero external dependencies
once images are pulled:

| Service | Image origin | Air-gap workaround |
|---|---|---|
| VM, vmagent, vmalert, vmauth, vmbackup, vmctl | docker.io/victoriametrics | Mirror to internal registry |
| Alertmanager | docker.io/prom | Mirror to internal registry |
| Grafana | docker.io/grafana | Mirror; pre-stage VM datasource plugin |
| OTel Collector | docker.io/otel | Mirror to internal registry |
| MinIO | docker.io/minio | Mirror, or replace with internal S3 |
| python:3.12-slim, llm-app, llm-traffic | docker.io/library | Mirror, build offline |

Network egress required at runtime: **none** (after images are pulled).

Outgoing alerts (Slack/PD/email) go through the corp egress proxy via
Alertmanager's HTTP webhooks. Configure proxy in Alertmanager's
http_config or use a webhook receiver inside the corp network.

---

## 11. Lab vs production differences

| Aspect | Lab default | Production recommendation |
|---|---|---|
| Mode | Single | Cluster (>= 500k series) |
| Auth | none | vmauth + TLS via reverse proxy |
| Retention | 12 months unified | tiered (7d hot / 6m warm / 3y cold) |
| Stream aggregation | disabled | enabled for cost metrics |
| Backups | vmbackup -> MinIO (Lab 5) | vmbackup -> production S3, encrypted |
| Alertmanager receivers | webhook.site placeholders | real Slack / PagerDuty |
| Grafana auth | anonymous viewer + admin/admin | OIDC / LDAP, RBAC, Teams |
| Network | docker bridge | NetworkPolicy / VPC ACLs |
| GPU exporter | simulated by `simulate_llm_metrics.py` | real DCGM exporter on each GPU node |
| Models | gpt-4o / claude / mistral fakes | real vLLM / Ollama / LiteLLM scrape |
| OTel collector deployment | one instance | DaemonSet (per-node) + central gateway |
| Trace storage | spanmetrics only (RED metrics) | Tempo / Jaeger for full trace storage |

---

## 12. Failure modes and recovery

### 12.1 vmagent down

- **Symptom** No new metrics in VM, panels go stale after `staleness=5m`.
- **Detection** `keep_last_value` panels still show last good value;
  `up{job=...} == 0` if vmagent self-monitored.
- **Recovery** vmagent has on-disk queue; restart and it resumes.

### 12.2 VictoriaMetrics OOM

- **Symptom** Container restarts; queries fail.
- **Detection** Grafana "Process RSS memory" panel hits ceiling; vmalert
  fires custom rule on `up{job="victoriametrics"} == 0`.
- **Recovery** Increase `--memory.allowedPercent` or migrate to Cluster.
- **Prevention** Cap cardinality (`--maxLabelsPerTimeseries=30`,
  `--storage.maxHourlySeries`).

### 12.3 OTel Collector crashloop

- **Symptom** Path B path stops; Path A still works.
- **Likely cause** Misconfigured connector / exporter.
- **Detection** `docker compose logs otel-collector | grep -i error`.
- **Recovery** Fix config, restart. The lab's `spanmetrics`-as-connector
  fix is one example.

### 12.4 Alertmanager not routing

- **Symptom** vmalert shows "firing", but no Slack notification.
- **Detection** Alertmanager UI -> alert is grouped but receiver shows
  errors.
- **Recovery** Webhook URL valid? Slack token expired? Inspect AM logs.

### 12.5 vmagent flag misconfiguration

- **Symptom** vmagent in `Restarting` state, `flag provided but not defined`.
- **Detection** `make diag-vmagent` shows the flag error on every restart.
- **Cause** vmagent flag names changed across versions. Common gotcha :
  using `-streamAggr.config` (doesn't exist in v1.99) instead of
  `-remoteWrite.streamAggr.config`.
- **Fix** Read `vmagent -help`, replace the flag, restart.

### 12.6 OTLP metric labels missing

- **Symptom** llm-app metrics arrive in VM without `service_name` label.
- **Detection** `make diag-otel` shows the actual labels present.
- **Cause** The OTel exporter appends the instrument unit to the metric
  name : `llm_request_duration_ms` with `unit="ms"` becomes
  `llm_request_duration_ms_milliseconds_*` in VM. Filter on
  `service_name=...` AND search for the suffixed name.

### 12.7 Disaster recovery (full data loss)

- **Drill** in `solutions/lab5-backup-airgap.md`:
  1. `docker compose down -v` (wipe volumes)
  2. `docker compose up -d victoriametrics`
  3. Run `vmrestore` from MinIO
  4. `docker compose restart victoriametrics`
- **RPO** 5 min (vmbackup interval) -- tunable
- **RTO** ~5 min for the lab (~30-60 min in production with 5M series)

---

## 13. Observability of the observability stack

The `VM Ops -- Cardinality & Performance` dashboard shows the meta-layer:

| Panel | Source metric | Why monitor |
|---|---|---|
| Active series | `vm_cache_entries{type=...}` | Detect cardinality bombs early |
| Samples ingested/s | `rate(vm_rows_inserted_total)` | Spot ingestion stalls |
| New series/s (churn) | `rate(vm_new_timeseries_created_total)` | Healthy: stable; unhealthy: monotonic climb |
| Disk usage | `vm_data_size_bytes` | Plan storage capacity |
| Process RSS | `process_resident_memory_bytes` | Catch OOM early |
| Query duration P99 | `vm_http_request_duration_seconds_bucket` | Find slow dashboards |
| Slow queries | `vm_slow_queries_total` | Find expensive expressions |

Plus the native cardinality endpoints (`/api/v1/status/tsdb`) accessible
from the dashboard's markdown panel and from vmui.

---

## 14. Trade-offs and known limitations

### 14.1 Why not Mimir / Cortex / Thanos?

| Concern | VM | Mimir/Cortex/Thanos |
|---|---|---|
| Operational complexity | 1 binary (Single) or 3 (Cluster) | Many binaries + object store + consensus |
| Cold storage | Built into Cluster | Object store offload required |
| RAM per series | ~1 KB | ~3-5 KB |
| MetricsQL extras | yes | no -- straight PromQL |
| Native OTel ingestion | yes | only via collector remote_write |
| Stream aggregation at ingest | yes (vmagent) | only post-ingestion recording rules |
| License | OSS Apache 2.0 (Cluster too) | OSS Apache 2.0 (some commercial extensions) |

VM trades some of the "Big Distributed System" elegance for simplicity
and bytes-on-disk efficiency. For LLM workloads where the bottleneck is
cardinality + retention + ingestion bursts, that's the right trade.

### 14.2 What VM doesn't do well

- **Logs** -- VM is metrics-only. Pair with Loki / Elastic for logs.
- **Traces** -- spanmetrics works, but for full trace storage use Tempo /
  Jaeger. The lab demonstrates the metric-derivation path, not full-trace
  storage.
- **Distributed transactions** -- if you need cross-cluster query
  federation with strong consistency, look at VictoriaMetrics Enterprise
  (downsampling, retention filters, ML anomaly via vmanomaly).

### 14.3 Limitations of this lab specifically

- `simulate_llm_metrics.py` does not call real LLMs -- token counts and
  costs are synthetic. Don't draw billing conclusions from lab data.
- `llm-app` exposes `/chat` and `/rag` but uses a fake `fake_completion`
  function -- no API keys required, but no real prompts run.
- Cluster mode in `docker-compose.cluster.yml` is **not migration-tested**;
  it's a clean-start variant.
- The 7 alert trigger scripts use direct `/api/v1/import/prometheus`
  pushes that bypass vmagent's relabeling. Production alerts come from
  real metrics.

---

## 15. Change history

| Version | Change |
|---|---|
| v1 | Single mode + 4 labs from Module 13 |
| v1.1 | Added Lab 5 (backup/vmauth/MinIO) + Cluster mode + 7 alert triggers + Makefile |
| v1.2 | Added llm-app (OTLP-instrumented FastAPI) + traffic generator |
| v1.3 | Added Lab 6 (MetricsQL exclusive), Lab 7 (cardinality), Lab 8 (stream aggregation), VM Differentiators dashboard, vmctl backfill, OTel exponential histograms |
| v1.4 | Added Home dashboard as Grafana landing page; emoji removal |
| v1.5 | This architecture document |
| v1.6 | OTel collector now scrapes VM/vmagent/vmalert/itself ; vmagent stream aggr flag corrected to `-remoteWrite.streamAggr.config` ; llm-app uses default histogram aggregation (exp parked) ; 3 ingestion paths visible in dashboard ; Home dashboard added ; demo loaders added |

---

## Appendix A -- Port reference

| Port | Service | Exposed on host |
|---|---|---|
| 8428 | VictoriaMetrics HTTP | yes |
| 8429 | vmagent (default) | no (internal) |
| 8480 | vminsert (Cluster) | yes (cluster-up) |
| 8481 | vmselect (Cluster) | yes (cluster-up) |
| 8482 | vmstorage (Cluster, internal) | no |
| 8880 | vmalert UI | yes |
| 9093 | Alertmanager | yes |
| 3000 | Grafana | yes |
| 4317 | OTel Collector OTLP gRPC | yes |
| 4318 | OTel Collector OTLP HTTP | yes |
| 9100 | llm-simulator /metrics | yes |
| 8001 | llm-app FastAPI | yes (mapped from container 8000) |
| 8427 | vmauth (Lab 5) | yes (lab5-airgap only) |
| 9000/9001 | MinIO API/console (Lab 5) | yes |

## Appendix B -- File reference

See README.md for the complete file tree. Key files:

- `docker-compose.yml` -- Single mode
- `docker-compose.cluster.yml` -- Cluster mode
- `airgap/docker-compose.airgap.yml` -- Lab 5 overlay
- `otel-collector-config.yaml` -- pipelines + spanmetrics connector
- `prometheus.yml` -- vmagent scrape jobs
- `streamAggr.yaml` -- ingest-time rollup config (Lab 8)
- `alertmanager.yml` -- routing rules
- `alerts/llm-quality.yml` -- 7 production alerts
- `alerts/recording-rules.yml` -- 8 recording rules
- `grafana/dashboards/*.json` -- 4 dashboards
- `airgap/vmauth.yml` -- multi-role auth (Lab 5)
- `solutions/lab*.md` -- lab walkthroughs
- `scripts/triggers/*.sh` -- alert trigger scripts
- `scripts/cardinality_explosion.sh` -- Lab 7 explosion
- `scripts/backfill_cost_csv.sh` -- vmctl historical import
- `scripts/verify_panels.sh` -- end-to-end panel audit
- `Makefile` / `make.ps1` / `make.cmd` -- shortcuts (Linux/Mac/Windows)
- `app/llm_app.py`, `app/otel_views.py`, `app/traffic_gen.py` -- OTel demo

---

## Appendix C -- Glossary

| Term | Meaning |
|---|---|
| **MetricsQL** | VictoriaMetrics' query language. Superset of PromQL. |
| **vmagent** | Lightweight Prometheus-compatible scraper + remote_writer. |
| **vmalert** | Rule evaluator for alerts and recording rules. |
| **vmauth** | Multi-tenant reverse proxy with auth and routing. |
| **vmbackup / vmrestore** | Snapshot-based backup tools to S3-compatible storage. |
| **vmctl** | CLI for migrations, backfills, diagnostics. |
| **vmui** | Built-in web UI on `:8428/vmui` -- query playground + cardinality explorer. |
| **vmanomaly** | Enterprise ML-based anomaly detection (not in this lab). |
| **OTel** | OpenTelemetry. |
| **OTLP** | OpenTelemetry Protocol (gRPC :4317 / HTTP :4318). |
| **spanmetrics** | OTel Collector connector that derives RED metrics from spans. |
| **DCGM** | NVIDIA Data Center GPU Manager -- the GPU metrics standard. |
| **vLLM** | High-throughput LLM inference server (paged attention). |
| **TTFT** | Time To First Token -- the streaming-LLM equivalent of TTFB. |
| **RAG** | Retrieval-Augmented Generation. |
| **SLO / SLI** | Service Level Objective / Indicator. |

---

**Contact** Erythix -- formations@erythix.io -- erythix.io
**Author** Samuel Desseaux, VictoriaMetrics Training Partner FR / Benelux / DE
