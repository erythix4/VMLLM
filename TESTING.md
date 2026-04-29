# Testing the lab -- step-by-step walkthrough

> Read this once before you start. 25 min from `git clone` to a populated
> Grafana dashboard with the full demo running.

---

## 1. Prerequisites

| Tool | Version | How to verify |
|---|---|---|
| Docker Desktop | recent | `docker version` |
| Docker Compose v2 | bundled with Desktop | `docker compose version` |
| Bash 4+ (or Git Bash on Windows) | for diagnostic scripts | `bash --version` |

8 GB RAM minimum on the host. The lab spins up 9 containers.

## 2. Start the stack

```bash
cd VLLM
make up                # docker compose up -d --build
sleep 60               # wait for first scrape + simulator warmup
make diagnose          # 5-step health check
```

Expected output of `make diagnose`:
```
[OK]  9 containers UP
[OK]  simulator exposes 60+ LLM metric lines
[OK]  VM has 200+ llm_requests_total series
[OK]  ingestion live: ~600 req/min
[OK]  15 alert/recording rules loaded
```

If any step fails, see Section 8 (Troubleshooting).

## 3. Open Grafana

http://localhost:3000   (admin / admin)

You land directly on **Home -- VictoriaMetrics LLM Lab** (the landing
dashboard with all the navigation you need). From there, three dashboards
are accessible :

| Dashboard | UID | When to open |
|---|---|---|
| **LLM Observability -- Production** | `llm-prod` | Day-to-day monitoring view |
| **VM Ops -- Cardinality & Performance** | `vm-ops` | When VM itself feels slow |
| **VM Differentiators -- Demo & Training** | `vm-diff` | POC / sales / training demo |

## 4. What you should see, by dashboard

### 4.1 LLM Observability -- Production (14 panels)

All 14 panels populated within 60 s:
- **Row 1 SLA** : Requests/min ~600, P99 latency 1-3s, error rate <1%, RAG z-score < 1
- **Row 2 Costs** : USD/min by model, daily projection, top tenants
- **Row 3 RAG** : retrieval scores ~0.78-0.86, context pressure, dropped chunks
- **Row 4 GPU** : TTFT P95, GPU memory, tokens/W

If you see "No data" anywhere here -> see Section 8.

### 4.2 VM Ops -- Cardinality & Performance (8 panels)

- Active series : few thousand
- Samples/s : ~50-100
- Disk usage, RSS memory : numbers, not flat
- VM CPU usage : 0.01-0.1
- Goroutines : ~30-100 per job
- **Scrape health : 4 cells GREEN** (`UP`) for victoriametrics, vmagent,
  vmalert, llm-simulator. If any is red, that scrape target is dead.

### 4.3 VM Differentiators -- Demo & Training (16 panels, 4 rows)

**This is the dashboard most panels start empty by design.** Empty panels
have an explicit `noValue` text describing what they need. To see them
light up, run the corresponding demo loader (Section 5).

Three rows of MetricsQL features + one row showing the **3 ingestion
paths side by side** (Prometheus client, OTLP metric, spanmetrics from
traces).

## 5. Run the full demo

```bash
make demo-all          # triggers conditions for all 4 rows in parallel
# wait 60-90 s
# refresh the dashboard
```

What this does:
- **Row 1 (MetricsQL exclusive)** : injects RAG drift + a latency outlier
  on `gpt-4o`. Within 30s : z-score climbs, `outliers_iqr` lights up
  gpt-4o, `share_le_over_time` grows.
- **Row 2 (Stream aggregation)** : enables `--remoteWrite.streamAggr.config`
  and restarts vmagent. Within 60s : `llm:cost_usd:agg1h` series appear,
  ratio panel shows raw vs aggregated cardinality, indicator switches
  from OFF (red) to ON (green).
- **Row 3 (OTel paths)** : verifies llm-app health, fires a burst against
  it, makes sure the OTLP and spanmetrics paths are producing data.
- **Row 4 (Cardinality)** : pushes 5000 demo series with a rotating
  `trace_id` label. Active series count jumps, "Lab 7 demo series count"
  goes red.

To revert :
```bash
make demo-clean        # stops drift sim, disables stream aggr, deletes demo series
```

## 6. The 4 Module-13 labs

Each is documented in its own file under `solutions/`. Reference flow :

```bash
# Lab 1 -- already done by `make up`
make lab1              # just prints the verification query for vmui

# Lab 2 -- write 5 MetricsQL queries
# Open http://localhost:8428/vmui and try queries from solutions/lab2-queries.md

# Lab 3 -- production alert
make lab3-drift        # injects RAG quality drop (15 min for alert to fire)
# watch http://localhost:8880 for RAGIndexDrift state going firing
make lab3-restore

# Lab 4 -- recording rules speed-up
# See solutions/lab4-recording-rules.md for benchmark commands
```

## 7. Bonus tracks

```bash
# Lab 5 -- backup, vmauth, air-gap (Module 12)
make lab5-airgap       # adds MinIO + vmbackup + vmauth
# See solutions/lab5-backup-airgap.md for restore drill

# Cluster mode (Module 3)
make down              # stop Single first
make cluster-up
make cluster-down

# Trigger any of the 7 production alerts
ls scripts/triggers/
bash scripts/triggers/03_llm_high_error_rate.sh
```

## 8. Troubleshooting

| Symptom | Run | What it tells you |
|---|---|---|
| Anything flat or empty | `make inspect` | which exact metric query returns 0 |
| vmagent in restart loop | `make diag-vmagent` | flag/config issue, network reachability |
| OTel panel empty | `make diag-otel` | llm-app health, label names actually present |
| `rag_retrieval_score_avg` empty | `make diag-simulator` | which simulator container is running |
| Need fresh start | `make clean && make up` | wipes volumes, full redeploy |

### 8.1 Known: 3 panels are empty by design

These panels stay at "0 / no data" in nominal regime -- it's correct,
not a bug :

- `outliers_iqr` (panel #2) : "No outliers detected" -- needs `make demo-row1`
- `share_le_over_time` (panel #3) : 0% -- means RAG quality is fine
- `Lab 7 demo series count` (panel #31) : 0 -- needs `make demo-row4`

Each panel's noValue text says exactly this. Don't troubleshoot them in
nominal regime; run the demo to see them respond.

### 8.2 Known: docker-compose `version: '3.8'` warning

Docker Compose v2 prints a deprecation warning on every `docker compose`
invocation. It's harmless. Edit the YAML to drop line 1 if it bothers you.

## 9. Cleanup

```bash
make clean             # docker compose down -v (wipes data volumes)
```

Or keep the data and just stop containers :

```bash
make down              # docker compose down (volumes preserved)
```

## 10. What to read next

| If you're a... | Start with |
|---|---|
| **Tester** validating the lab | this file (you are here) |
| **Architect** evaluating VM | `ARCHITECTURE.md` |
| **Trainer** running a session | the **Home** Grafana dashboard, then `solutions/labN.md` |
| **Sales engineer** on a POC | run `make demo-all`, demo each row of *VM Differentiators* dashboard |
| **SRE** prepping for prod | `solutions/lab5-backup-airgap.md` + `ARCHITECTURE.md` Section 8-12 |
| **Developer** writing instrumentation | `app/llm_app.py` (Module 6.1 OTel SDK reference) |
