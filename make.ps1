<#
.SYNOPSIS
    Windows PowerShell shim for the lab Makefile -- same target names.
.EXAMPLE
    .\make.ps1 up
    .\make.ps1 lab6
    .\make.ps1 lab8-streamaggr
.NOTES
    Requires Docker Desktop + PowerShell 5.1+ (default on Windows 10/11).
    For convenience, use the bundled make.cmd so you can type:  make lab6
#>
param(
    [Parameter(Position=0)]
    [string]$Target = "help"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Show-Help {
    Write-Host "VictoriaMetrics LLM Observability Lab -- Windows shortcuts" -ForegroundColor Cyan
    Write-Host ""
    $targets = @(
        @{Name="help";              Desc="Show this help"},
        @{Name="up";                Desc="Start the full Single-mode stack"},
        @{Name="down";              Desc="Stop the stack (keep volumes)"},
        @{Name="build";             Desc="(Re)build local images"},
        @{Name="rebuild";           Desc="Full rebuild: down, build, up"},
        @{Name="logs";              Desc="Tail logs of every service"},
        @{Name="ps";                Desc="List containers"},
        @{Name="diagnose";          Desc="Run end-to-end health checks"},
        @{Name="lab1";              Desc="Lab 1 -- helper hint to vmui"},
        @{Name="lab3-drift";        Desc="Lab 3 -- inject RAG score drift"},
        @{Name="lab3-restore";      Desc="Lab 3 -- restore nominal RAG score"},
        @{Name="lab5-airgap";       Desc="Lab 5 -- start MinIO + vmauth + vmbackup"},
        @{Name="lab6";              Desc="Lab 6 -- MetricsQL exclusive showcase"},
        @{Name="lab7-explode";      Desc="Lab 7 -- explode cardinality"},
        @{Name="lab7-cleanup";      Desc="Lab 7 -- delete cardinality demo series"},
        @{Name="lab8-streamaggr";   Desc="Lab 8 -- enable vmagent stream aggregation"},
        @{Name="lab8-disable";      Desc="Lab 8 -- disable stream aggregation"},
        @{Name="cluster-up";        Desc="Start the Cluster-mode stack"},
        @{Name="cluster-down";      Desc="Stop the Cluster-mode stack"},
        @{Name="alerts";            Desc="List alert-trigger scripts"},
        @{Name="backfill";          Desc="Backfill 30 days of historical cost CSV"},
        @{Name="clean";             Desc="Stop everything and wipe volumes"}
    )
    foreach ($t in $targets) {
        Write-Host ("  {0,-20}" -f $t.Name) -ForegroundColor Yellow -NoNewline
        Write-Host (" {0}" -f $t.Desc)
    }
    Write-Host ""
    Write-Host "Usage:  .\make.ps1 <target>     or     make <target>  (via make.cmd shim)" -ForegroundColor DarkGray
}

switch ($Target.ToLower()) {

    "help" { Show-Help; break }

    "up" {
        docker compose up -d --build
        Write-Host "Wait ~60s, then:  make diagnose" -ForegroundColor Green
        break
    }

    "down" { docker compose down; break }

    "build" { docker compose build; break }

    "rebuild" {
        docker compose down
        docker compose build
        docker compose up -d
        break
    }

    "logs" { docker compose logs -f --tail=50; break }

    "ps"   { docker compose ps; break }

    "diagnose" {
        # Translate diagnose.sh inline so we don't need bash on Windows
        Write-Host "=== 1. Container status ===" -ForegroundColor Cyan
        docker compose ps

        Write-Host "`n=== 2. Simulator: /metrics ===" -ForegroundColor Cyan
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:9100/metrics" -UseBasicParsing -TimeoutSec 5
            $count = ($r.Content -split "`n" | Where-Object { $_ -match "^(llm_|rag_|DCGM_)" }).Count
            Write-Host "[OK] simulator exposes $count LLM metric lines" -ForegroundColor Green
        } catch {
            Write-Host "[FAIL] simulator unreachable -- check 'docker compose logs llm-simulator'" -ForegroundColor Red
        }

        Write-Host "`n=== 3. VM has llm_requests_total ? ===" -ForegroundColor Cyan
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8428/api/v1/query?query=count(llm_requests_total)" -UseBasicParsing -TimeoutSec 5
            $v = ($r.Content | ConvertFrom-Json).data.result
            if ($v.Count -gt 0) { Write-Host "[OK] $($v[0].value[1]) llm_requests_total series" -ForegroundColor Green }
            else { Write-Host "[FAIL] no series yet -- check 'docker compose logs vmagent'" -ForegroundColor Red }
        } catch { Write-Host "[FAIL] VM unreachable" -ForegroundColor Red }

        Write-Host "`n=== 4. Live request rate ===" -ForegroundColor Cyan
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8428/api/v1/query?query=sum(rate(llm_requests_total%5B1m%5D))*60" -UseBasicParsing -TimeoutSec 5
            $v = ($r.Content | ConvertFrom-Json).data.result
            if ($v.Count -gt 0) { Write-Host "[OK] live rate: $([math]::Round([double]$v[0].value[1],1)) req/min" -ForegroundColor Green }
            else { Write-Host "[WARN] no live rate yet -- wait 60-90s" -ForegroundColor Yellow }
        } catch { Write-Host "[FAIL]" -ForegroundColor Red }

        Write-Host "`n=== 5. vmalert rules ===" -ForegroundColor Cyan
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8880/api/v1/rules" -UseBasicParsing -TimeoutSec 5
            $g = ($r.Content | ConvertFrom-Json).data.groups
            $count = ($g | ForEach-Object { $_.rules.Count } | Measure-Object -Sum).Sum
            Write-Host "[OK] $count alert/recording rules loaded" -ForegroundColor Green
        } catch { Write-Host "[WARN] vmalert not yet ready" -ForegroundColor Yellow }
        break
    }

    "lab1" {
        Write-Host "Open http://localhost:8428/vmui and run:" -ForegroundColor Cyan
        Write-Host "  sum by (model) (rate(llm_requests_total[1m])) * 60"
        Write-Host "Open http://localhost:3000 (admin/admin) for the dashboard."
        break
    }

    "lab3-drift" {
        docker compose stop llm-simulator
        docker compose run -d --name llm-simulator-drift llm-simulator --rps 10 --models 3 --score-drift 0.5
        Write-Host "Wait ~15 min. Watch http://localhost:8880 for RAGIndexDrift firing." -ForegroundColor Green
        break
    }

    "lab3-restore" {
        docker rm -f llm-simulator-drift 2>$null | Out-Null
        docker compose start llm-simulator
        Write-Host "Restored. Alerts will resolve after their evaluation window." -ForegroundColor Green
        break
    }

    "lab5-airgap" {
        docker compose -f docker-compose.yml -f airgap/docker-compose.airgap.yml up -d
        Write-Host "MinIO console http://localhost:9001  (admin/admin12345)" -ForegroundColor Green
        Write-Host "vmauth        http://localhost:8427  (basic auth -- 3 roles)" -ForegroundColor Green
        break
    }

    "lab6" {
        Write-Host "Open http://localhost:8428/vmui and try queries from solutions/lab6-metricsql-exclusive.md" -ForegroundColor Cyan
        if (Test-Path ".\solutions\lab6-metricsql-exclusive.md") {
            Get-Content ".\solutions\lab6-metricsql-exclusive.md" | Select-Object -First 30
        }
        break
    }

    "lab7-explode" {
        bash scripts/cardinality_explosion.sh
        break
    }

    "lab7-cleanup" {
        $url = 'http://localhost:8428/api/v1/admin/tsdb/delete_series?match[]={__name__="llm_demo_bad_metric"}'
        Invoke-WebRequest -Uri $url -Method Post -UseBasicParsing | Out-Null
        Write-Host "Demo series deleted." -ForegroundColor Green
        break
    }

    "lab8-streamaggr" {
        # Toggle the streamAggr flag in docker-compose.yml
        $f = ".\docker-compose.yml"
        $c = Get-Content $f -Raw
        if ($c -match "      # - '--remoteWrite.streamAggr") {
            $c = $c -replace "      # - '--remoteWrite.streamAggr", "      - '--remoteWrite.streamAggr"
            Set-Content -Path $f -Value $c -NoNewline
            docker compose restart vmagent
            Write-Host "Stream aggregation enabled. After 1m: query 'llm:cost_usd:agg1h' in vmui." -ForegroundColor Green
        } else {
            Write-Host "Already enabled (or pattern not found)." -ForegroundColor Yellow
        }
        break
    }

    "lab8-disable" {
        $f = ".\docker-compose.yml"
        $c = Get-Content $f -Raw
        $c = $c -replace "(?m)^      - '--remoteWrite.streamAggr", "      # - '--remoteWrite.streamAggr"
        Set-Content -Path $f -Value $c -NoNewline
        docker compose restart vmagent
        Write-Host "Stream aggregation disabled." -ForegroundColor Green
        break
    }

    "cluster-up"   { docker compose -f docker-compose.cluster.yml up -d --build; break }
    "cluster-down" { docker compose -f docker-compose.cluster.yml down; break }

    "alerts" {
        Write-Host "Available alert-trigger scripts (run with bash or WSL):" -ForegroundColor Cyan
        Get-ChildItem -Path ".\scripts\triggers" -Filter "*.sh" | ForEach-Object {
            Write-Host "  bash scripts/triggers/$($_.Name)"
        }
        break
    }

    "backfill" {
        bash scripts/backfill_cost_csv.sh
        break
    }

    "clean" {
        docker compose down -v
        docker compose -f docker-compose.cluster.yml down -v 2>$null
        docker compose -f docker-compose.yml -f airgap/docker-compose.airgap.yml down -v 2>$null
        Write-Host "Cleaned." -ForegroundColor Green
        break
    }

    "demo-row1" {
        bash scripts/demo/row1_metricsql.sh; break
    }
    "demo-row2" {
        bash scripts/demo/row2_streamaggr.sh; break
    }
    "demo-row3" {
        bash scripts/demo/row3_otel.sh; break
    }
    "demo-row4" {
        bash scripts/demo/row4_cardinality.sh; break
    }
    "demo-all" {
        bash scripts/demo/all.sh; break
    }
    "demo-clean" {
        bash scripts/demo/clean.sh; break
    }

    "inspect" {
        & "$PSScriptRoot\scripts\inspect_vm.ps1"
        break
    }

    default {
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Write-Host ""
        Show-Help
        exit 1
    }
}
