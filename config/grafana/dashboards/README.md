# Grafana Dashboards

## Recommended Community Dashboards

Import these pre-built dashboards for instant visibility:

### 1. Node Exporter Full (ID: 1860)
**Perfect for system monitoring**
- CPU, memory, disk, network metrics
- Swap usage tracking
- Disk I/O monitoring
- System load

**To import:**
1. Go to Grafana → Dashboards → Import
2. Enter ID: `1860`
3. Select Prometheus datasource
4. Click Import

### 2. Docker Container & Host Metrics (ID: 179)
**Monitor all containers**
- Container CPU & memory usage
- Network I/O per container
- Disk I/O per container
- Container status

**To import:**
1. Enter ID: `179`
2. Select Prometheus datasource
3. Click Import

### 3. Traefik 2 (ID: 12250)
**Monitor reverse proxy**
- HTTP requests per second
- Response codes distribution
- Backend status
- Request duration

**To import:**
1. Enter ID: `12250`
2. Select Prometheus datasource
3. Click Import

### 4. Loki Dashboard Quick Search (ID: 12611)
**View logs from all containers**
- Search logs by container
- Filter by log level
- Time-based log viewing
- Error detection

**To import:**
1. Enter ID: `12611`
2. Select Loki datasource
3. Click Import

## Custom Panels to Add

You can create custom dashboards with these key queries:

### Swap Usage Alert
```promql
(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / 1024 / 1024 / 1024
```
Set alert threshold at 2GB

### Data Drive Space
```promql
100 - ((node_filesystem_avail_bytes{mountpoint="/media/data"} / node_filesystem_size_bytes{mountpoint="/media/data"}) * 100)
```
Set warning at 85%

### Container Memory by Service
```promql
container_memory_usage_bytes{name!=""}
```

### Top 5 CPU Containers
```promql
topk(5, rate(container_cpu_usage_seconds_total{name!=""}[5m]))
```

## Dashboard Organization

Recommended folder structure in Grafana:
- **System** - Node Exporter dashboard
- **Containers** - Docker metrics
- **Services** - Traefik, media apps
- **Logs** - Loki dashboards
