# Grafana Setup Guide

This guide covers setting up Grafana with automatic datasource provisioning and pre-configured dashboards.

## Automatic Datasource Configuration

Grafana can automatically configure Prometheus and Loki datasources on startup.

### Create Datasources Configuration

Run these commands to set up datasource provisioning:

```bash
# Create datasources directory (requires sudo due to Grafana container ownership)
sudo mkdir -p config/grafana/provisioning/datasources

# Create the datasources configuration file
sudo tee config/grafana/provisioning/datasources/datasources.yml > /dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s
      httpMethod: POST

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false
    jsonData:
      maxLines: 1000
      derivedFields:
        - datasourceUid: Prometheus
          matcherRegex: "traceID=(\\w+)"
          name: TraceID
          url: "$${__value.raw}"
EOF

# Fix ownership (Grafana runs as UID 1000)
sudo chown -R 1000:1000 config/grafana/provisioning
```

### Verify Datasources

After restarting Grafana:

1. Navigate to **Configuration → Data Sources**
2. You should see:
   - **Prometheus** (default) - Green checkmark
   - **Loki** - Green checkmark

## Dashboard Provisioning

Grafana can also automatically load dashboards from JSON files.

### Setup Dashboard Provisioning

```bash
# Create dashboards provisioning config
sudo tee config/grafana/provisioning/dashboards.yml > /dev/null <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: 'Home Server'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
EOF

# Fix ownership
sudo chown 1000:1000 config/grafana/provisioning/dashboards.yml
```

### Import Dashboards

The following dashboards are included in this repository:

1. **Home Server Overview** (`config/grafana/dashboards/home-server-overview.json`)
   - System resources (CPU, RAM, Swap, Disk)
   - Container status and resource usage
   - Disk usage trends
   - Swap usage monitoring

2. **Media Pipeline** (`config/grafana/dashboards/media-pipeline.json`)
   - Sonarr/Radarr/Prowlarr statistics
   - Download activity and speeds
   - Library growth over time
   - Disk space for media

3. **Network & Security** (`config/grafana/dashboards/network-security.json`)
   - Traefik request metrics
   - HTTP status code distribution
   - Authentication failures
   - VPN status and bandwidth
   - AdGuard DNS statistics

Dashboards will automatically reload when the JSON files are updated.

## Manual Datasource Configuration (Alternative)

If automatic provisioning doesn't work, configure datasources manually:

### Add Prometheus

1. Go to **Configuration → Data Sources → Add data source**
2. Select **Prometheus**
3. Configure:
   - **Name:** Prometheus
   - **URL:** `http://prometheus:9090`
   - **Access:** Server (default)
4. Click **Save & Test**

### Add Loki

1. Go to **Configuration → Data Sources → Add data source**
2. Select **Loki**
3. Configure:
   - **Name:** Loki
   - **URL:** `http://loki:3100`
   - **Access:** Server (default)
4. Click **Save & Test**

## Importing Dashboards Manually

If dashboard provisioning doesn't work:

1. Go to **Dashboards → Import**
2. Click **Upload JSON file**
3. Select a dashboard file from `config/grafana/dashboards/`
4. Configure:
   - **Folder:** Home Server (or create new)
   - **Prometheus datasource:** Prometheus
   - **Loki datasource:** Loki
5. Click **Import**

Repeat for each dashboard.

## Troubleshooting

### Datasources Don't Appear

Check Grafana logs:
```bash
docker compose logs grafana | grep -i datasource
```

Common issues:
- Ownership problem: `sudo chown -R 1000:1000 config/grafana/provisioning`
- YAML syntax error: Validate with `yamllint config/grafana/provisioning/datasources/datasources.yml`
- Grafana needs restart: `docker compose restart grafana`

### Dashboard Import Fails

- Verify JSON syntax: `jq . config/grafana/dashboards/dashboard-name.json`
- Check Grafana version compatibility
- Ensure datasources are configured first

### Metrics Not Showing

1. Verify Prometheus is scraping targets:
   - Navigate to `http://localhost:9090/targets`
   - All targets should show "UP" status

2. Check Prometheus configuration:
   ```bash
   docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
   ```

3. Verify containers are exposing metrics:
   ```bash
   # Test Traefik metrics
   curl http://localhost:8082/metrics
   
   # Test Loki metrics
   curl http://localhost:3100/metrics
   ```

### Loki Logs Not Appearing

1. Check Promtail is running:
   ```bash
   docker compose ps promtail
   docker compose logs promtail --tail=50
   ```

2. Verify Promtail configuration:
   ```bash
   docker compose exec promtail cat /etc/promtail/config.yaml
   ```

3. Test Loki query:
   ```bash
   # List log streams
   curl -G -s http://localhost:3100/loki/api/v1/label/__name__/values
   ```

## Alertmanager Integration

Once Alertmanager is configured, add it as a contact point:

1. Go to **Alerting → Contact points**
2. Click **New contact point**
3. Configure:
   - **Name:** Alertmanager
   - **Integration:** Alertmanager
   - **URL:** `http://alertmanager:9093`
4. Click **Save contact point**

This allows Grafana alerts to route through Alertmanager for unified alert management.

## Useful Queries

### Prometheus Queries

System metrics:
```promql
# Memory usage percentage
100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

# Swap usage
node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes

# Disk usage percentage
100 * (1 - (node_filesystem_avail_bytes{mountpoint="/media/data"} / node_filesystem_size_bytes{mountpoint="/media/data"}))

# CPU usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Container memory usage
container_memory_usage_bytes{name!=""}
```

### Loki Queries

Container logs:
```logql
# All logs from a container
{container_name="sonarr"}

# Errors in last hour
{container_name=~".+"} |= "error" | line_format "{{.container_name}}: {{.log}}"

# Failed auth attempts
{container_name="traefik"} |~ "401|403"

# Recent errors across all containers
{container_name=~".+"} |= "level=error" or |= "ERROR" or |= "FATAL"
```

## Next Steps

1. Configure Alertmanager for webhook notifications (see `docs/alertmanager-setup.md`)
2. Create custom dashboards for specific use cases
3. Set up Grafana authentication via Authentik (OAuth2)
4. Configure alert rules in Grafana (in addition to Prometheus alerts)
5. Export dashboards regularly for backup: **Dashboard → Settings → JSON Model → Copy**

## References

- [Grafana Provisioning Docs](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Prometheus Datasource Config](https://grafana.com/docs/grafana/latest/datasources/prometheus/)
- [Loki Datasource Config](https://grafana.com/docs/grafana/latest/datasources/loki/)
- [Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/json-model/)
