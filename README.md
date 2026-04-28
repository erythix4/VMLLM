# Lab -- VictoriaMetrics as an LLM Observability Backend

Companion lab for the *Premium Training Guide -- VictoriaMetrics as an LLM
Observability Backend* (Erythix). Implements the **4 labs of Module 13**
plus 8 bonus tracks demonstrating VM features that PromQL cannot match.

## SETUP

```bash
git clone https://github.com/erythix4/aiobs-lab
cd aiobs-lab/labs/victoriametrics-llm
make up                    # starts the 9-container stack
sleep 60
make diagnose              # verify everything is wired
make demo-all              # populate every demo panel for ~10 min
```

Open http://localhost:3000 (admin / admin) -- you land on the **Home**
dashboard with everything navigable from there.

**For testers** : read [`TESTING.md`](TESTING.md) end-to-end -- 25 min
walkthrough with expected results.
**For architects** : [`ARCHITECTURE.md`](ARCHITECTURE.md) -- components,
data flows, scaling, security, failure modes.

---

## Stack (Single mode default)

| Service | Port | Role |
|---|---|---|
| VictoriaMetrics | 8428 | TSDB + MetricsQL + vmui |
| OTel Collector | 4317 / 4318 | OTLP gRPC + HTTP, scrapes Prometheus targets |
| vmagent | -- | Prometheus-style scraping + remote_write + stream aggregation |
| vmalert | 8880 | Alert rules + recording rules evaluation |
| Alertmanager | 9093 | Routing + notifications |
| Grafana | 3000 | 4 dashboards (Home, LLM Prod, VM Ops, VM Differentiators) |
| llm-simulator | 9100 | Synthetic Prometheus-client workload (10 rps) |
| llm-app | 8001 | OTLP-instrumented FastAPI demo (RAG endpoints) |
| llm-traffic | -- | Continuous client hitting llm-app at 5 rps |

## Three ingestion paths run side by side

The lab demonstrates the same metric names landing in VM via three
distinct paths, so you can compare patterns visually :

| Path | Source | Pipeline | Distinguishing label |
|---|---|---|---|
| **Prometheus client** | `llm-simulator` | Prometheus exposition -> vmagent scrape -> remote_write | `job=llm-simulator` |
| **OTLP metric push** | `llm-app` (OTel SDK) | OTLP gRPC -> OTel collector -> remote_write | `service_name=llm-demo-app`, name suffix `_milliseconds` |
| **OTLP traces -> spanmetrics** | `llm-app` traces | OTLP gRPC -> spanmetrics connector -> remote_write | metric name `duration_milliseconds`, dims `gen_ai_*` and `rag_*` |

Row 3 of the **VM Differentiators** dashboard plots all three paths' P99
latency next to each other.

---

## The full lab roster

### Module 13 of the guide -- 4 core labs

| Lab | Goal | Time | Doc |
|---|---|---|---|
| 1 | Deploy stack, ingest first metrics | 30 min | [TESTING.md](TESTING.md) |
| 2 | Write 5 MetricsQL queries | 40 min | [`solutions/lab2-queries.md`](solutions/lab2-queries.md) |
| 3 | Configure RAGIndexDrift alert | 25 min | `make lab3-drift` / `make lab3-restore` |
| 4 | Recording rules speed-up | 20 min | [`solutions/lab4-recording-rules.md`](solutions/lab4-recording-rules.md) |

### Bonus enrichments

| Track | Goal | How |
|---|---|---|
| Lab 5 | Backup, vmauth, air-gap (Module 12) | [`solutions/lab5-backup-airgap.md`](solutions/lab5-backup-airgap.md) -- `make lab5-airgap` |
| Cluster mode | VM Cluster (Module 3) | `make cluster-up` / `make cluster-down` |
| Alert triggers | Fire any of 7 prod alerts on demand | `bash scripts/triggers/<name>.sh` |
| OTLP demo app | Module 6.1 reference | `app/llm_app.py` |
| vmctl backfill | Historical cost CSV import | `make backfill` |

### VM-differentiator labs

| Lab | Goal | Doc |
|---|---|---|
| 6 | MetricsQL functions PromQL cannot do | [`solutions/lab6-metricsql-exclusive.md`](solutions/lab6-metricsql-exclusive.md) |
| 7 | Cardinality observation & remediation | [`solutions/lab7-cardinality.md`](solutions/lab7-cardinality.md) |
| 8 | vmagent stream aggregation | [`solutions/lab8-stream-aggregation.md`](solutions/lab8-stream-aggregation.md) |

---

## Demo loaders -- make panels show their value

Many *VM Differentiators* panels are flat in idle conditions because the
features they showcase (outlier detection, anomaly score, share-below-SLO)
need a non-nominal signal. The demo loaders create that signal :

```bash
make demo-row1     # MetricsQL row -- RAG drift + gpt-4o latency outlier
make demo-row2     # Stream aggregation row -- enables --remoteWrite.streamAggr.config
make demo-row3     # OTel histograms row -- verifies + bursts traffic to llm-app
make demo-row4     # Cardinality row -- pushes 5000 demo series
make demo-all      # all 4 in sequence (full live demo)
make demo-clean    # revert everything
```

Each panel that starts empty has a `noValue` text that says exactly which
demo loader to run.

---

## Diagnostic & verification

| Command | What it does |
|---|---|
| `make diagnose` | 5-step end-to-end health check |
| `make inspect` | tests every panel query and reports `[EMPTY]` |
| `make diag-vmagent` | vmagent status + logs + targets + reachability |
| `make diag-otel` | llm-app health + OTel labels + collector logs |
| `make diag-simulator` | which simulator container is producing metrics |

`make help` lists all 30+ Makefile targets.

---

## File tree

```
labs/victoriametrics-llm/
|-- README.md                         # this file
|-- TESTING.md                        # tester walkthrough
|-- ARCHITECTURE.md                   # technical reference
|-- docker-compose.yml                # Single mode (default)
|-- docker-compose.cluster.yml        # Cluster mode bonus
|-- otel-collector-config.yaml        # OTel + spanmetrics + 5 scrape jobs
|-- prometheus.yml                    # vmagent scrape (also active)
|-- alertmanager.yml                  # routing rules
|-- streamAggr.yaml                   # Lab 8 -- 1m windows for the lab
|-- alerts/{llm-quality,recording-rules}.yml
|-- app/                              # OTLP-instrumented FastAPI
|   |-- llm_app.py                    # demo app (Module 6.1)
|   |-- otel_views.py                 # exp histogram views (parked)
|   |-- traffic_gen.py                # continuous client
|   |-- requirements.txt  Dockerfile  Dockerfile.traffic
|-- airgap/                           # Lab 5 + cluster overlays
|   |-- docker-compose.airgap.yml     # MinIO + vmbackup + vmauth
|   |-- vmauth.yml                    # multi-role auth
|   |-- otel-cluster.yaml grafana-cluster-datasources.yml
|-- grafana/
|   |-- dashboards/
|   |   |-- dashboard-home.json              # landing page guide
|   |   |-- dashboard-llm-prod.json          # business KPIs (14 panels)
|   |   |-- dashboard-vm-ops.json            # SRE / VM self-monitoring (8)
|   |   `-- dashboard-vm-differentiators.json# POC / training (16, 4 rows)
|   `-- provisioning/{datasources,dashboards}/
|-- scripts/
|   |-- triggers/                     # 7 alert-trigger scripts
|   |-- demo/                         # 6 demo loaders for VM Differentiators
|   |-- cardinality_explosion.sh
|   |-- backfill_cost_csv.sh
|   |-- inspect_vm.sh inspect_vm.ps1  # query every panel, find EMPTY
|   |-- diagnose_vmagent.sh
|   |-- diagnose_otel.sh
|   |-- diagnose_simulator.sh
|   `-- verify_panels.sh
|-- simulate_llm_metrics.py           # Module 6.2 metrics generator
|-- diagnose.sh                       # end-to-end health check (Bash)
|-- Makefile  make.ps1  make.cmd      # 30+ shortcuts (Linux/Mac/Windows)
`-- solutions/
    |-- lab2-queries.md      lab4-recording-rules.md
    |-- lab5-backup-airgap.md
    |-- lab6-metricsql-exclusive.md
    |-- lab7-cardinality.md  lab8-stream-aggregation.md
```

---

## What's special about this lab vs the official Prometheus version

Eight features below are **VM-only differentiators** for LLM workloads ;
each is shown live in a dashboard panel + documented in `solutions/` :

| # | Feature | Where in the lab |
|---|---|---|
| 1 | MetricsQL functions PromQL doesn't have (`outliers_iqr`, `share_le_over_time`, `quantiles_over_time`, `histogram_avg`, `keep_last_value`) | `solutions/lab6-metricsql-exclusive.md` + VM Differentiators Row 1 |
| 2 | vmagent stream aggregation at ingest time | `streamAggr.yaml` + Row 2 |
| 3 | Native cardinality endpoints | VM Ops dashboard + `solutions/lab7-cardinality.md` |
| 4 | OTLP native ingest with auto label conversion | `app/llm_app.py` + Row 3 |
| 5 | Spanmetrics connector for traces -> RED metrics | OTel collector config + Row 3 |
| 6 | Cluster mode with replicationFactor | `docker-compose.cluster.yml` |
| 7 | vmctl historical backfill from CSV | `scripts/backfill_cost_csv.sh` |
| 8 | vmauth multi-role + vmbackup to S3 | `airgap/` + `solutions/lab5-backup-airgap.md` |

---

## Cleanup

```bash
make clean        # docker compose down -v on every overlay
```

## References

- Training guide PDF: `guide_victoriametrics_llm_en.docx`
- Slide deck: `vm_llm_observability_deck.pptx`
- VictoriaMetrics docs: https://docs.victoriametrics.com
- MetricsQL: https://docs.victoriametrics.com/metricsql
- Stream aggregation: https://docs.victoriametrics.com/stream-aggregation

Contact: **contact@erythix.tech** -- erythix.tech
*Samuel Desseaux -- VictoriaMetrics Training Partner FR / Benelux / DE*
