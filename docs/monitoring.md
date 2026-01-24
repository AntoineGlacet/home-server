---
title: "Monitoring & Observability"
weight: 1
description: "Complete guide to the monitoring stack: Prometheus, Grafana, Loki, and alerting"
---

Complete guide to the monitoring stack: Prometheus, Grafana, Loki, and alerting.

## Table of Contents

- [Overview](#overview)
- [Prometheus](#prometheus)
- [Grafana](#grafana)
- [Loki & Promtail](#loki--promtail)
- [Exporters](#exporters)
- [Alerting](#alerting)
- [Glances](#glances)

## Overview

### Monitoring Stack

| Component | Purpose | Access |
| --- | --- | --- |
| **Prometheus** | Metrics collection & storage | http://localhost:9090 |
| **Grafana** | Dashboards & alerting | https://grafana.antoineglacet.com |
| **Loki** | Log aggregation | http://loki:3100 (internal) |
| **Promtail** | Log collection | Daemon (no UI) |
| **cAdvisor** | Container metrics | http://localhost:8080 |
| **Node Exporter** | Host system metrics | http://172.17.0.1:9100 |
| **Blackbox Exporter** | Network probes | Internal |
| **Glances** | Real-time monitor | https://glances.antoineglacet.com |

### Data Flow

```
Metrics:  Exporters → Prometheus → Grafana → Dashboards
Logs:     Containers → Promtail → Loki → Grafana → Explore
Alerts:   Prometheus → Grafana Alerting → Discord
```

## Prometheus

### Overview

Prometheus scrapes metrics from various targets and stores them in a time-series database.

**Access:** http://localhost:9090

### Scrape Targets

Configured in `config/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'prometheus'        # Self-monitoring
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'     # Host metrics
    static_configs:
      - targets: ['172.17.0.1:9100']

  - job_name: 'cadvisor'          # Container metrics
    scrape_interval: 30s
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'traefik'           # Reverse proxy metrics
    scrape_interval: 15s
    static_configs:
      - targets: ['traefik:8082']

  - job_name: 'loki'              # Log system metrics
    scrape_interval: 30s
    static_configs:
      - targets: ['loki:3100']

  - job_name: 'blackbox_icmp'     # Network latency (ping)
    static_configs:
      - targets:
          - 10.13.1.1              # Gateway
          - 8.8.8.8                # Google DNS
          - 1.1.1.1                # Cloudflare DNS
```

### Viewing Targets

```bash
# Check target status in UI
# http://localhost:9090/targets

# Via API
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Unhealthy targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'
```

### Query Examples

```promql
# CPU usage by container
rate(container_cpu_usage_seconds_total[5m])

# Memory usage
container_memory_usage_bytes / 1024 / 1024  # Convert to MB

# Disk space free
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100

# Network traffic
rate(node_network_receive_bytes_total[5m])

# HTTP request rate (Traefik)
rate(traefik_service_requests_total[5m])
```

### Storage & Retention

Data stored in: `data/prometheus/`

**Default retention:** 15 days

**Change retention:**

```yaml
# In docker-compose.yml, add to command:
command:
  - '--storage.tsdb.retention.time=30d'
  - '--storage.tsdb.path=/prometheus'
```

### Backups

```bash
# Backup Prometheus data
tar -czf ~/prometheus-backup-$(date +%F).tar.gz data/prometheus/

# Restore
docker compose stop prometheus
tar -xzf ~/prometheus-backup-2026-01-24.tar.gz
docker compose start prometheus
```

## Grafana

### Overview

Grafana visualizes metrics from Prometheus and logs from Loki.

**Access:** https://grafana.antoineglacet.com (auto-login via Authentik)

### Datasources

Provisioned automatically from `config/grafana/provisioning/datasources/`:

1. **Prometheus** - Metrics
2. **Loki** - Logs

**Verify datasources:**
- Grafana → Configuration → Data sources
- Or: http://localhost:3000/api/datasources

### Dashboards

#### Pre-configured Dashboards

Located in `config/grafana/dashboards/`:

1. **Node Exporter Full** - Host metrics (CPU, RAM, disk, network)
2. **Docker Container Metrics** - Per-container resource usage
3. **Traefik Dashboard** - Request rates, errors, response times
4. **Loki Logs** - Centralized log viewer

#### Adding Custom Dashboards

**Method 1: Via UI**
1. Create dashboard in Grafana
2. Share → Export → Save JSON
3. Copy to `config/grafana/dashboards/my-dashboard.json`
4. Restart Grafana

**Method 2: Import**
1. Find dashboard on https://grafana.com/dashboards
2. Copy dashboard ID
3. Grafana → Import → Enter ID

**Method 3: Provisioning**

Add to `config/grafana/provisioning/dashboards/`:

```yaml
# dashboards.yml
apiVersion: 1
providers:
  - name: 'default'
    folder: ''
    type: file
    options:
      path: /etc/grafana/dashboards
```

### OAuth Integration

Grafana uses Authentik for authentication.

**Configuration in `.env`:**

```bash
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=xxx
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=xxx
GF_AUTH_OAUTH_AUTO_LOGIN=true
GF_SERVER_ROOT_URL=https://grafana.antoineglacet.com
```

See [Authentik documentation](authentik.md#grafana-oauth-integration) for setup.

### Useful Queries

#### Loki (Logs)

```logql
# All logs from a container
{container_name="traefik"}

# Error logs across all containers
{job="docker"} |= "error"

# Failed authentication attempts
{container_name="authentik-server"} |= "failed" |= "login"

# Traefik 5xx errors
{container_name="traefik"} |~ "HTTP/[0-9.]+ 5[0-9]{2}"

# Rate of errors
rate({job="docker"} |= "error"[5m])
```

#### Prometheus (Metrics)

```promql
# Container CPU usage
sum(rate(container_cpu_usage_seconds_total{name!=""}[5m])) by (name) * 100

# Container memory usage (MB)
sum(container_memory_usage_bytes{name!=""}) by (name) / 1024 / 1024

# Disk usage
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Network throughput
rate(node_network_receive_bytes_total{device="eth0"}[5m])

# Traefik response time (95th percentile)
histogram_quantile(0.95, rate(traefik_service_request_duration_seconds_bucket[5m]))
```

## Loki & Promtail

### Overview

Loki aggregates logs from all Docker containers. Promtail collects and ships logs to Loki.

### How It Works

1. Promtail tails `/var/lib/docker/containers/` (via Docker socket mount)
2. Adds labels (container name, image, etc.)
3. Streams logs to Loki
4. Loki indexes labels, stores logs
5. Query via Grafana → Explore → Loki

### Configuration

**Promtail:** `config/promtail/config.yaml`

```yaml
scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        target_label: 'container_name'
```

**Loki:** `config/loki/local-config.yaml`

### Storage & Retention

**Data location:** `data/loki/`

**Retention** (default: 744h = 31 days):

```yaml
# config/loki/local-config.yaml
limits_config:
  retention_period: 744h

# Add compactor for cleanup:
compactor:
  working_directory: /loki/compactor
  shared_store: filesystem
  retention_enabled: true
  retention_delete_delay: 2h
```

### Querying Logs

```bash
# Via Grafana
# https://grafana.antoineglacet.com → Explore → Loki

# Common queries:
{container_name="traefik"}
{job="docker"} |= "error"
{container_name=~"authentik.*"} |= "failed"

# Live tail in Grafana (top right: Live button)
```

### Log Labels

Available labels:
- `container_name`: Docker container name
- `container_id`: Full container ID
- `job`: Always "docker"
- `stream`: stdout or stderr

## Exporters

### Node Exporter

Collects host system metrics.

**Runs on:** Host network (port 9100)

**Metrics:**
- CPU usage
- Memory usage
- Disk I/O
- Network traffic
- System load
- Filesystem usage

**Example queries:**

```promql
# CPU usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Disk free
node_filesystem_avail_bytes{mountpoint="/"}
```

### cAdvisor

Collects Docker container metrics.

**Access:** http://localhost:8080

**Metrics:**
- CPU usage per container
- Memory usage per container
- Network I/O per container
- Filesystem I/O per container

**Example queries:**

```promql
# Container CPU usage
rate(container_cpu_usage_seconds_total{name!=""}[5m])

# Container memory
container_memory_usage_bytes{name!=""}

# Top 10 CPU consumers
topk(10, rate(container_cpu_usage_seconds_total{name!=""}[5m]))
```

### Blackbox Exporter

Performs network probes (ICMP, HTTP, DNS).

**Configuration:** `config/blackbox-exporter/blackbox.yml`

**Probes:**
- ICMP (ping) to: Gateway, Google DNS, Cloudflare DNS, MS Teams
- HTTP checks: google.com, teams.microsoft.com, cloudflare.com
- DNS queries to: 8.8.8.8, 1.1.1.1

**Example queries:**

```promql
# Ping latency
probe_duration_seconds{job="blackbox_icmp"}

# HTTP probe success rate
probe_success{job="blackbox_http"}

# Internet down alert
probe_success{instance="8.8.8.8"} == 0
```

## Alerting

### Migration to Grafana Unified Alerting

**Note:** Alerting migrated from Alertmanager to Grafana (Jan 2026).

See `ALERTING_MIGRATION.md` for full details.

### Alert Configuration

**Location:** `config/grafana/provisioning/alerting/`

```
alerting/
├── rules.yml          # Alert rules
├── policies.yml       # Notification policies
└── contactpoints.yml  # Discord webhook
```

### Alert Rules

Example alert rules in `rules.yml`:

```yaml
groups:
  - name: infrastructure
    interval: 1m
    rules:
      - alert: HighCPU
        expr: (100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        annotations:
          summary: High CPU usage detected
          
      - alert: HighMemory
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.90
        for: 5m
        annotations:
          summary: High memory usage detected
          
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
        for: 10m
        annotations:
          summary: Disk space critically low
```

### Contact Points

Configure Discord webhook in `.env`:

```bash
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN
```

**Test webhook:**

```bash
curl -H "Content-Type: application/json" \
  -d '{"content":"Test alert from home server"}' \
  $DISCORD_WEBHOOK_URL
```

### Managing Alerts

**View alerts:**
- Grafana → Alerting → Alert rules

**Silence alerts:**
- Grafana → Alerting → Silences → New silence

**View alert history:**
- Grafana → Alerting → Alert instances

### Common Alert Rules

```promql
# Container down
absent(up{job="cadvisor"})

# Container restarting
rate(container_last_seen{name!=""}[5m]) > 0

# Traefik service error rate
rate(traefik_service_requests_total{code=~"5.."}[5m]) > 0.05

# Internet connectivity
probe_success{instance="8.8.8.8"} == 0

# Certificate expiry (30 days)
(traefik_tls_certs_not_after - time()) / 86400 < 30
```

## Glances

### Overview

Real-time system monitoring with web UI.

**Access:** https://glances.antoineglacet.com

### Features

- CPU usage (per core)
- Memory and swap
- Disk I/O
- Network traffic
- Docker container stats
- Process list
- System sensors (temperature)
- File system usage

### Configuration

**Auto-refresh:** 2 seconds (default)

**Disable update check:** `GLANCES_OPT=-w --disable-check-update`

### API Access

Glances exposes REST API:

```bash
# Get system stats
curl http://glances:61208/api/3/all

# CPU info
curl http://glances:61208/api/3/cpu

# Memory info
curl http://glances:61208/api/3/mem

# Docker containers
curl http://glances:61208/api/3/docker
```

### Useful Views

- **Per-process:** Click on process name
- **Disk I/O:** Shows read/write rates
- **Network:** In/out bandwidth
- **Alerts:** Red highlights for thresholds

## Best Practices

### Monitoring

1. **Check dashboards daily** - Quick health overview
2. **Set up alerts** - Get notified of issues
3. **Review logs weekly** - Catch patterns early
4. **Monitor trends** - Identify capacity needs

### Performance

1. **Tune scrape intervals** - Balance freshness vs load
2. **Set retention policies** - Don't store forever
3. **Add resource limits** - Prevent resource hogging
4. **Clean up old data** - Reclaim disk space

### Alerting

1. **Start conservative** - Add alerts gradually
2. **Tune thresholds** - Avoid alert fatigue
3. **Test notifications** - Ensure Discord works
4. **Document response** - How to fix each alert
