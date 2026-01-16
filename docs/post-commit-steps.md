# Post-Commit Setup Steps

This document outlines manual steps required after applying the infrastructure improvements commit.

## 🚨 Priority 1: Performance Optimization (DO THIS FIRST!)

### Apply Swap Tuning

This will immediately improve your interactive session responsiveness:

```bash
# Apply swappiness change immediately
sudo sysctl vm.swappiness=10

# Make it permanent
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf

# Verify
cat /proc/sys/vm/swappiness
# Should output: 10
```

**Expected result:** SSH sessions respond instantly, less disk thrashing

---

## 🔧 Priority 2: Grafana Datasource Configuration

Grafana container runs as UID 1000, so datasource provisioning requires sudo:

```bash
# Create datasources configuration
sudo mkdir -p config/grafana/provisioning/datasources

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
EOF

# Fix ownership
sudo chown -R 1000:1000 config/grafana/provisioning

# Restart Grafana to load datasources
docker compose restart grafana
```

Verify:
- Navigate to Grafana: http://localhost:3000
- Go to Configuration → Data Sources
- Both Prometheus and Loki should show green status

---

## 📊 Priority 3: Grafana Dashboards

### Option A: Import Pre-Built Dashboards (Recommended)

Since the dashboard JSON files are large, use community dashboards as a starting point:

**Home Server Overview Dashboard:**
1. Go to Grafana → Dashboards → Import
2. Use Dashboard ID: `1860` (Node Exporter Full)
3. Select Prometheus datasource
4. Click Import
5. Customize as needed

**cAdvisor/Docker Dashboard:**
1. Go to Dashboards → Import
2. Use Dashboard ID: `193` (Docker Monitoring)
3. Select Prometheus datasource
4. Click Import

**Loki Logs Dashboard:**
1. Go to Dashboards → Import
2. Use Dashboard ID: `13639` (Loki Dashboard)
3. Select Loki datasource
4. Click Import

### Option B: Create Custom Dashboards

Follow the guide in `docs/grafana-setup.md` for creating custom dashboards with:
- Swap usage monitoring
- Disk space trends
- Container resource usage
- Media pipeline stats

---

## 🔔 Priority 4: Enable Traefik Metrics

Traefik needs metrics endpoint enabled. Add this to docker-compose.yml in the `traefik` service command section:

```yaml
traefik:
  command:
    # ... existing commands ...
    - --metrics.prometheus=true
    - --metrics.prometheus.addEntryPointsLabels=true
    - --metrics.prometheus.addServicesLabels=true
    - --entryPoints.metrics.address=:8082
```

Then restart Traefik:
```bash
docker compose up -d traefik
```

Verify metrics are available:
```bash
curl http://localhost:8082/metrics | head -20
```

---

## ⚙️ Priority 5: Apply Resource Limits

The docker-compose.yml now includes resource limits for top memory consumers. To apply them:

```bash
# Restart services with new limits
docker compose up -d authentik-server radarr sonarr flaresolverr bazarr

# Monitor to ensure services start correctly
docker compose logs authentik-server --tail=50
docker stats
```

**Services with limits:**
- `authentik-server`: 768MB limit
- `radarr`: 512MB limit
- `sonarr`: 384MB limit
- `flaresolverr`: 256MB limit
- `bazarr`: 256MB limit

If any service fails to start, check logs and increase the limit if needed.

---

## 🛡️ Priority 6: Verify Security Headers

After restarting Traefik, verify security headers are being set:

```bash
# Test from external domain
curl -I https://your-domain.com

# Should see headers like:
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff
# Strict-Transport-Security: max-age=31536000
```

---

## 📦 Priority 7: Setup Automated Backups

### Configure Daily PostgreSQL Backups

Add to crontab:
```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /home/antoine/home-server/scripts/backup-postgres.sh >> /var/log/postgres-backup.log 2>&1
```

Test the backup script manually first:
```bash
cd /home/antoine/home-server
./scripts/backup-postgres.sh
```

### Verify Duplicati Backups

Run the validation script:
```bash
./scripts/validate-backups.sh
```

Fix any issues reported.

---

## 🔍 Priority 8: Configure Alertmanager Webhook

Create Alertmanager configuration:

```bash
# Create config directory
mkdir -p config/alertmanager

# Create configuration file
cat > config/alertmanager/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'webhook'

receivers:
  - name: 'webhook'
    webhook_configs:
      - url: 'YOUR_WEBHOOK_URL_HERE'
        send_resolved: true

# Example for Discord:
# - name: 'discord'
#   webhook_configs:
#     - url: 'https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_TOKEN/slack'
#       send_resolved: true

# Example for Slack:
# - name: 'slack'
#   slack_configs:
#     - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
#       channel: '#alerts'
#       title: 'Home Server Alert'
EOF

# Add Alertmanager to docker-compose.yml (if not already done)
# See docker-compose.yml for the alertmanager service definition

# Start Alertmanager
docker compose up -d alertmanager
```

Test alerts:
```bash
# Trigger a test alert
curl -X POST http://localhost:9093/api/v1/alerts -d '[{
  "labels": {
    "alertname": "TestAlert",
    "severity": "info"
  },
  "annotations": {
    "summary": "Test alert from home server"
  }
}]'
```

---

## ✅ Verification Checklist

After completing all steps, verify everything is working:

- [ ] Swappiness is set to 10: `cat /proc/sys/vm/swappiness`
- [ ] Swap usage is decreasing: `free -h` (check over time)
- [ ] Grafana datasources are connected (green status)
- [ ] Dashboards are showing data
- [ ] Traefik metrics are being scraped by Prometheus
- [ ] Prometheus is collecting metrics: http://localhost:9090/targets (all UP)
- [ ] Resource limits are applied: `docker inspect authentik-server | grep -A5 Memory`
- [ ] Security headers are present: `curl -I https://your-domain.com`
- [ ] Backup scripts are working: `./scripts/validate-backups.sh`
- [ ] PostgreSQL backups are being created
- [ ] Alert manager is receiving alerts
- [ ] All containers are running: `docker compose ps`
- [ ] No errors in logs: `docker compose logs --tail=100`

---

## 🚀 Performance Monitoring

After 24 hours, check the improvements:

```bash
# Run health check
./scripts/health-check.sh

# Check swap usage trend
free -h

# Check disk I/O wait (should be low now)
iostat -x 1 5

# View Grafana dashboards for historical trends
```

**Expected improvements:**
- ✅ Swap usage <500MB (down from 1.9GB)
- ✅ SSH sessions respond instantly
- ✅ Lower disk I/O wait times
- ✅ More consistent container performance
- ✅ Visibility into all system metrics

---

## 📚 Additional Documentation

- `docs/performance-tuning.md` - Detailed swap and performance optimization guide
- `docs/grafana-setup.md` - Grafana configuration and dashboard creation
- `README.md` - Updated with OptiPlex hardware specs

---

## 🆘 Troubleshooting

### Grafana Datasources Not Appearing

```bash
# Check Grafana logs
docker compose logs grafana | grep -i datasource

# Verify file ownership
ls -la config/grafana/provisioning/datasources/

# Should be: drwxr-xr-x 1000 1000

# Fix if needed
sudo chown -R 1000:1000 config/grafana/provisioning/
docker compose restart grafana
```

### Prometheus Not Scraping Targets

```bash
# Check Prometheus config syntax
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml

# View scrape targets
curl http://localhost:9090/targets

# Check Traefik metrics endpoint
curl http://localhost:8082/metrics
```

### Resource Limits Causing OOM Kills

```bash
# Check for OOM kills
docker compose logs | grep -i "killed\|oom"
sudo dmesg | grep -i oom

# If services are being killed, increase limits in docker-compose.yml
# Then restart: docker compose up -d <service-name>
```

### High Swap Despite swappiness=10

```bash
# Clear swap if safe (ensure >4GB free RAM first!)
free -h
sudo swapoff -a && sudo swapon -a

# Monitor swap usage
watch -n 5 'free -h'

# Check for memory leaks in containers
docker stats --no-stream | sort -k7 -h -r
```

---

## 🎯 Next Steps

Once everything is stable:

1. **Create custom Grafana alerts** for your specific thresholds
2. **Set up Vaultwarden** for secret management (separate commit)
3. **Configure Authentik OAuth** for Grafana SSO
4. **Add CI/CD validation** (GitHub Actions, pre-commit hooks)
5. **Document your specific alert thresholds** based on observed metrics
6. **Consider upgrading to 16GB RAM** for future growth

---

Need help? Check:
- Container logs: `docker compose logs <service> --tail=100`
- System health: `./scripts/health-check.sh`
- Backup status: `./scripts/validate-backups.sh`
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000
