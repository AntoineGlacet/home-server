# Deployment Checklist - Infrastructure Improvements

**Date:** 2026-01-16
**Commits:** 568b47d + 3e81ad9

---

## ✅ COMPLETED - No Action Needed

- ✅ Swappiness reduced to 10 (you already did this!)
- ✅ All code changes committed
- ✅ Docker Compose configuration validated (syntax OK)
- ✅ Resource limits configured
- ✅ Security headers configured
- ✅ Alertmanager configured
- ✅ Grafana auto-provisioning configured
- ✅ Image versions pinned

---

## 🔴 REQUIRED BEFORE DEPLOYMENT

### 1. Add Discord Webhook to .env

You need to add your Discord webhook URL to the `.env` file:

```bash
# Edit your .env file
nano .env

# Add this line (replace with your actual webhook URL from Uptime Kuma):
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_TOKEN/slack
```

**IMPORTANT:** Add `/slack` to the end of your Discord webhook URL for Alertmanager compatibility.

**To find your webhook:**
- Check Uptime Kuma notification settings
- Or create a new webhook in Discord: Server Settings → Integrations → Webhooks

---

## 🚀 DEPLOYMENT PROCESS

### Step 1: Verify Prerequisites

```bash
# Confirm swappiness is set
cat /proc/sys/vm/swappiness
# Should output: 10

# Confirm Discord webhook is in .env
grep DISCORD_WEBHOOK_URL .env
# Should show your webhook URL

# Verify configuration
docker compose config > /dev/null && echo "✓ Config valid" || echo "✗ Error"
```

### Step 2: Pull New Images

**This will download:**
- Alertmanager (new service)
- Updated versions of pinned images

```bash
docker compose pull
```

**Expected download size:** ~500MB-1GB depending on what's cached

### Step 3: Restart Services

**Option A: Restart Everything (Recommended)**
```bash
docker compose up -d
```

**Option B: Restart Only Changed Services**
```bash
# Restart services with resource limits
docker compose up -d authentik-server radarr sonarr flaresolverr bazarr

# Restart monitoring stack
docker compose up -d prometheus grafana traefik

# Start new Alertmanager
docker compose up -d alertmanager
```

### Step 4: Verify Deployment

```bash
# Check all containers are running
docker compose ps

# Check for errors
docker compose logs --tail=50 alertmanager
docker compose logs --tail=50 traefik
docker compose logs --tail=50 grafana

# Run health check
./scripts/health-check.sh
```

---

## 📊 POST-DEPLOYMENT VERIFICATION

### 1. Grafana Datasources (5 minutes)

Visit: http://localhost:3000 (or https://grafana.your-domain.com)

**Check datasources:**
1. Go to Configuration → Data Sources
2. You should see:
   - ✅ Prometheus (green check, default)
   - ✅ Loki (green check)

**If datasources are missing:**
```bash
# Check Grafana logs
docker compose logs grafana | grep -i datasource

# Restart Grafana
docker compose restart grafana
```

### 2. Import Dashboards (10 minutes)

In Grafana, go to Dashboards → Import and add these:

**Essential Dashboards:**
1. **Node Exporter Full** (ID: 1860)
   - Shows: CPU, RAM, **swap usage**, disk space
   - **This will show your swap improvement!**

2. **Docker Container Metrics** (ID: 179)
   - Shows: Container resource usage
   - Verify resource limits are working

3. **Traefik** (ID: 12250)
   - Shows: HTTP requests, status codes
   - Verify metrics endpoint is working

4. **Loki Logs** (ID: 12611)
   - Shows: Container logs
   - Search and filter logs

### 3. Prometheus Targets (2 minutes)

Visit: http://localhost:9090/targets

**All should be UP:**
- ✅ prometheus (1/1 up)
- ✅ node_exporter (1/1 up)
- ✅ cadvisor (1/1 up)
- ✅ traefik (1/1 up)
- ✅ loki (1/1 up)

**If traefik is DOWN:**
- Metrics endpoint needs to be enabled (it should be in docker-compose.yml already)
- Check: `curl http://localhost:8082/metrics`

### 4. Alertmanager (5 minutes)

Visit: http://localhost:9093 (or https://alertmanager.your-domain.com)

**Test Discord webhook:**
```bash
# Send test alert
curl -X POST http://localhost:9093/api/v1/alerts -d '[{
  "labels": {
    "alertname": "TestAlert",
    "severity": "info"
  },
  "annotations": {
    "summary": "Test alert from Alertmanager - if you see this in Discord, it works!"
  }
}]'
```

**Check Discord:** You should receive a message in your alerts channel

**If no Discord message:**
1. Check Alertmanager logs: `docker compose logs alertmanager`
2. Verify webhook URL in .env is correct
3. Ensure `/slack` is at the end of the URL

### 5. Security Headers (2 minutes)

Test from external domain:
```bash
curl -I https://your-domain.com
```

**Should see headers:**
```
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Strict-Transport-Security: max-age=31536000
Referrer-Policy: strict-origin-when-cross-origin
```

### 6. Resource Limits (Ongoing)

Monitor containers with limits:
```bash
docker stats

# Watch for these containers:
# - authentik-server (should stay under 768MB)
# - radarr (should stay under 512MB)
# - sonarr (should stay under 384MB)
# - flaresolverr (should stay under 256MB)
# - bazarr (should stay under 256MB)
```

**If any container is killed (OOM):**
1. Check logs: `docker compose logs <service-name>`
2. Increase limit in docker-compose.yml
3. Restart: `docker compose up -d <service-name>`

### 7. Swap Usage (24 hours)

Monitor swap improvement:
```bash
# Check immediately
free -h

# Check after 24 hours - should be much lower
free -h
```

**Expected:**
- Before: 1.9GB swap used
- After: <500MB swap used

---

## ⚠️ TROUBLESHOOTING

### Services Won't Start

```bash
# Check docker compose logs
docker compose logs --tail=100

# Check specific service
docker compose logs <service-name>

# Restart specific service
docker compose restart <service-name>
```

### Grafana Dashboards Not Loading

```bash
# Restart Grafana
docker compose restart grafana

# Check provisioning
docker compose exec grafana ls -la /etc/grafana/provisioning/datasources/
docker compose exec grafana ls -la /etc/grafana/provisioning/dashboards/
```

### Prometheus Not Scraping

```bash
# Check Prometheus config
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Check targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets'
```

### Alertmanager Not Sending Alerts

```bash
# Check logs
docker compose logs alertmanager

# Verify config
docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# Test webhook manually
curl -X POST "YOUR_DISCORD_WEBHOOK_URL" -H "Content-Type: application/json" -d '{"text":"Test from Alertmanager"}'
```

### Resource Limits Too Low (OOM Kills)

```bash
# Check for OOM kills
sudo dmesg | grep -i oom

# Increase limits in docker-compose.yml and restart
docker compose up -d <service-name>
```

---

## 📈 MONITORING YOUR IMPROVEMENTS

### Swap Usage Trending Down
After deployment, you should see:
- **Immediate:** Swap stops growing
- **6 hours:** Swap decreases to <1GB
- **24 hours:** Swap stable at <500MB
- **Result:** SSH sessions respond instantly

View in Grafana:
- Dashboard: Node Exporter Full
- Panel: Memory Usage
- Query: `(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / 1024 / 1024 / 1024`

### Resource Limits Working
View in Grafana:
- Dashboard: Docker Container Metrics
- Check each service stays within limits
- No OOM kills in logs

### Security Headers Active
- All HTTPS responses include security headers
- Traefik metrics show reduced attack surface
- Rate limiting prevents abuse

---

## 🎯 SUCCESS CRITERIA

After 24 hours, you should have:

- ✅ Swap usage <500MB (down from 1.9GB)
- ✅ All Prometheus targets UP
- ✅ Grafana showing 4+ dashboards
- ✅ Alertmanager sending test alerts to Discord
- ✅ Security headers on all HTTPS responses
- ✅ No container OOM kills
- ✅ All services running healthy
- ✅ SSH sessions respond instantly

---

## 🔄 ROLLBACK PROCEDURE

If anything goes wrong:

```bash
# Option 1: Revert last commit
git revert HEAD
docker compose pull
docker compose up -d

# Option 2: Revert both commits
git revert HEAD~1..HEAD
docker compose pull
docker compose up -d

# Option 3: Hard reset (loses commits)
git reset --hard HEAD~2
docker compose pull
docker compose up -d
```

**Note:** Your swappiness change (vm.swappiness=10) will persist through rollback - that's good!

---

## 📞 NEXT STEPS

After successful deployment:

1. **Monitor for 24 hours**
   - Watch swap usage decrease
   - Check for any OOM kills
   - Verify alerts are working

2. **Create Grafana alerts** (optional)
   - Set up alerts for critical thresholds
   - Route through Alertmanager to Discord

3. **Fine-tune resource limits** (if needed)
   - Increase limits if services are killed
   - Decrease if usage is much lower than limit

4. **Add Vaultwarden** (future enhancement)
   - Secret management server
   - Migrate secrets from .env

---

**Questions? Check:**
- `IMPLEMENTATION_STATUS.md` - Full implementation details
- `docs/post-commit-steps.md` - Additional configuration steps
- `docs/performance-tuning.md` - Swap optimization details
- `docs/grafana-setup.md` - Grafana configuration help

**Ready to deploy?** ✅ Complete steps 1-4 above!
