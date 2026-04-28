# Lab 5 -- Backup, vmauth, air-gap (Module 12)

*Estimated 35 min · level: advanced*

## Goal

Stand up the production-grade controls from Module 12: object-storage backups
of VictoriaMetrics via `vmbackup`, a multi-role reverse proxy (`vmauth`) so
each consumer authenticates with the right scope, and an air-gap-capable
S3-compatible store (`MinIO`) so nothing leaves the lab network.

## What the overlay adds

```
airgap/
  docker-compose.airgap.yml   # MinIO + vmbackup + vmauth
  vmauth.yml                  # multi-role auth config
```

| Service        | Port  | Role                                              |
|----------------|-------|---------------------------------------------------|
| minio          | 9000  | S3 API for backups (admin / admin12345)           |
| minio (UI)     | 9001  | Web console                                       |
| vmbackup       | -     | Snapshot + push to s3://vm-backups every 5 min    |
| vmauth         | 8427  | Reverse proxy with 3 roles in front of VM         |

## Walkthrough

```bash
make lab5-airgap
```

Wait ~30 s, then verify each control:

### 1. Backups land in MinIO
Open http://localhost:9001 (admin / admin12345) -> bucket `vm-backups/auto`
should fill within 5-6 minutes. You should see two object directories
(metadata + data parts).

### 2. vmauth multi-role check
```bash
# Read-only (Grafana role): allowed
curl -u grafana:grafana-password \
    'http://localhost:8427/api/v1/query?query=sum(rate(llm_requests_total[1m]))'

# Read with the wrong role: 401
curl -u otel-collector:otel-password \
    'http://localhost:8427/api/v1/query?query=up'

# Write (OTel role): allowed
echo 'demo_metric 1' | curl -u otel-collector:otel-password \
    --data-binary @- 'http://localhost:8427/api/v1/write'

# Admin: everything
curl -u admin:admin-password 'http://localhost:8427/-/healthy'
```

### 3. Restore drill (DR exercise)
```bash
# Wipe VictoriaMetrics data
docker compose stop victoriametrics
docker volume rm victoriametrics-llm_vm-data
docker compose up -d victoriametrics

# Restore from the most recent backup
docker run --rm --network victoriametrics-llm_default \
    -e AWS_ACCESS_KEY_ID=admin -e AWS_SECRET_ACCESS_KEY=admin12345 \
    -v victoriametrics-llm_vm-data:/var/lib/vm-data \
    victoriametrics/vmrestore:v1.99.0 \
    -storageDataPath=/var/lib/vm-data \
    -src=s3://vm-backups/auto \
    -customS3Endpoint=http://minio:9000 \
    -s3ForcePathStyle=true

docker compose restart victoriametrics
```

Re-open Grafana: data should reappear up to the last snapshot.

### 4. Compliance checklist (Module 12.2)

| Compliance point                | Verified by |
|---------------------------------|-------------|
| No PII in metric labels         | `topk(20, count by (__name__)({__name__!=""}))` -> ensure no `user_id`, `query`, `email` labels |
| 3-year cost retention           | `--retentionPeriod=24m` on cost-only VM tier (production) |
| Encryption in transit           | TLS in front of vmauth (Nginx/Caddy), not enabled in lab |
| Tenant isolation                | vmauth `url_prefix` per tenant |
| Backup                          | vmbackup -> S3 (MinIO in lab) |
| Dashboard access (SSO)          | Grafana OIDC/LDAP (production) |
