# VictoriaMetrics LLM Observability Lab -- shortcuts
.PHONY: help up down build rebuild logs ps diagnose lab1 lab3-drift lab3-restore lab5-airgap clean alerts cluster-up cluster-down

help:  ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

up:  ## Start the full Single-mode stack
	docker compose up -d --build
	@echo "Wait ~60s, then:  make diagnose"

down:  ## Stop the stack (keep volumes)
	docker compose down

build:  ## (Re)build local images
	docker compose build

rebuild: down build up  ## Full rebuild: down, build, up

logs:  ## Tail logs of every service
	docker compose logs -f --tail=50

ps:  ## List containers
	docker compose ps

diagnose:  ## Run end-to-end health checks
	bash diagnose.sh

# --- Lab shortcuts ---

lab1:  ## Lab 1 -- run a manual query in vmui
	@echo "Open http://localhost:8428/vmui and run:"
	@echo "  sum by (model) (rate(llm_requests_total[1m])) * 60"
	@echo "Open http://localhost:3000 (admin/admin) for the dashboard."

lab3-drift:  ## Lab 3 -- inject RAG score drift to fire RAGIndexDrift
	docker compose stop llm-simulator
	docker compose run -d --name llm-simulator-drift llm-simulator --rps 10 --models 3 --score-drift 0.5
	@echo "Wait ~15 min. Watch http://localhost:8880 for RAGIndexDrift firing."

lab3-restore:  ## Lab 3 -- restore nominal RAG score
	-docker rm -f llm-simulator-drift
	docker compose start llm-simulator

# --- Lab 5: air-gap / backup / vmauth ---

lab5-airgap:  ## Lab 5 -- start MinIO + vmauth + vmbackup overlay
	docker compose -f docker-compose.yml -f airgap/docker-compose.airgap.yml up -d
	@echo "MinIO console http://localhost:9001  (admin/admin12345)"
	@echo "vmauth  http://localhost:8427  (basic auth: grafana / otel-collector)"

# --- Cluster mode ---

cluster-up:  ## Start the Cluster-mode stack (vminsert/vmstorage/vmselect)
	docker compose -f docker-compose.cluster.yml up -d --build

cluster-down:  ## Stop the Cluster-mode stack
	docker compose -f docker-compose.cluster.yml down

# --- Alert triggers ---

alerts:  ## List the available alert-trigger scripts
	@ls scripts/triggers/

clean:  ## Stop everything and wipe volumes
	docker compose down -v
	-docker compose -f docker-compose.cluster.yml down -v
	-docker compose -f docker-compose.yml -f airgap/docker-compose.airgap.yml down -v

lab6:  ## Lab 6 -- run the MetricsQL exclusive showcase queries
	@echo "Open http://localhost:8428/vmui and try queries from solutions/lab6-metricsql-exclusive.md"

lab7-explode:  ## Lab 7 -- explode cardinality on purpose
	bash scripts/cardinality_explosion.sh

lab7-cleanup:  ## Lab 7 -- delete the cardinality demo series
	curl -X POST 'http://localhost:8428/api/v1/admin/tsdb/delete_series?match[]={__name__="llm_demo_bad_metric"}'

lab8-streamaggr:  ## Lab 8 -- enable vmagent stream aggregation
	sed -i "s|# - '--remoteWrite.streamAggr|- '--streamAggr|" docker-compose.yml
	docker compose restart vmagent
	@echo "After 1m: query 'llm:cost_usd:agg1h' in vmui."

backfill:  ## Backfill 30 days of historical cost CSV via vmctl
	bash scripts/backfill_cost_csv.sh

# === Per-row demo loaders for VM Differentiators dashboard ===
demo-row1:  ## Demo Row 1 -- MetricsQL exclusive (drift + outlier)
	bash scripts/demo/row1_metricsql.sh

demo-row2:  ## Demo Row 2 -- enable stream aggregation
	bash scripts/demo/row2_streamaggr.sh

demo-row3:  ## Demo Row 3 -- OTel exp histograms verify + burst
	bash scripts/demo/row3_otel.sh

demo-row4:  ## Demo Row 4 -- cardinality explosion
	bash scripts/demo/row4_cardinality.sh

demo-all:  ## Run all 4 row demos (full guided demo)
	bash scripts/demo/all.sh

demo-clean:  ## Revert all demo conditions
	bash scripts/demo/clean.sh

inspect:  ## Probe every panel query and report which metric is missing
	bash scripts/inspect_vm.sh

diag-vmagent:  ## Diagnose why vmagent is not scraping
	bash scripts/diagnose_vmagent.sh

diag-simulator:  ## Diagnose why simulator metrics are missing
	bash scripts/diagnose_simulator.sh

diag-otel:  ## Diagnose why OTel-pushed metrics from llm-app are missing
	bash scripts/diagnose_otel.sh
