---
title: "Deployment Notes - 2026-01-16"
weight: 2
description: "Deployment notes and observations from January 2026"
---

## Summary

This deployment fixes critical issues from the previous monitoring infrastructure deployment and completes the Discord alerting setup.

## What Was Fixed

### 1. **Traefik v3.2 Incompatibility** ⚠️ CRITICAL FIX

**Problem:** All web services were inaccessible after previous deployment.

**Root Cause:** Traefik v3.2.5 had an outdated Docker client library incompatible with Docker API v1.44+
```
Error: client version 1.24 is too old. Minimum supported API version is 1.44
```

**Solution:** Changed to `traefik:latest` (currently v3.6.7)
- ✅ Compatible with Docker 29.1.4 (API 1.52)
- ✅ All routes rediscovered
- ✅ All services accessible

**Impact:** **HIGH** - Restored access to all web UIs (homepage, Grafana, etc.)

---

### 2. **AdGuard & Syncthing Version Conflicts**

**Problem:** Both services in restart loops due to config schema incompatibility

**Details:**
- AdGuard: Config schema v32 too new for pinned v0.107.54
- Syncthing: Config schema v51 too new for pinned v1.28

**Solution:** Changed both to `:latest` tags
- AdGuard: Using version compatible with schema v32
- Syncthing: Using version compatible with schema v51

**Impact:** **MEDIUM** - Services now stable

---

### 3. **Prometheus Scrape Target Failures**

**Problem:** 2 of 5 targets failing to scrape

**Issues Found:**
- `node_exporter:9100` - DNS resolution failed (uses `host` network mode)
- `traefik:8082` - Metrics endpoint returning 404 (wrong port)

**Solutions:**
- node_exporter: Changed to `172.17.0.1:9100` (host IP)
- traefik: Changed to `traefik:8080` (API port with metrics)

**Impact:** **MEDIUM** - Full metrics collection restored

---

### 4. **Discord Alerts Setup** ✅ NEW FEATURE

**Problem:** Discord Slack-compatible webhook incompatible with Alertmanager format

**Solution:** Deployed `benjojo/alertmanager-discord` bridge
```
Prometheus → Alertmanager → alertmanager-discord → Discord
```

**Configuration:**
- New service: `alertmanager-discord` (port 9094)
- Environment variable: `DISCORD_WEBHOOK_URL` (without `/slack` suffix)
- Alertmanager routes to bridge via webhook
- Bridge formats alerts for Discord native API

**Testing:** ✅ Test alerts successfully delivered to Discord

**Impact:** **HIGH** - Full alerting capability now operational

---

## Files Changed

### Configuration Files

1. **config/alertmanager/alertmanager.yml**
   - Changed receiver from `null` to `discord`
   - Points to alertmanager-discord bridge
   - Simplified group_by configuration

2. **config/prometheus/prometheus.yml**
   - Fixed node_exporter target: `172.17.0.1:9100`
   - Fixed traefik target: `traefik:8080`

3. **.env.example**
   - Updated `DISCORD_WEBHOOK_URL` documentation
   - Removed `/slack` suffix (no longer needed)

### Docker Compose

1. **docker-compose.yml**
   - **traefik**: `v3.2` → `latest` (v3.6.7)
   - **adguard**: `v0.107.54` → `latest`
   - **syncthing**: `1.28` → `latest`
   - **alertmanager**: Added `user: "1000:1000"`, removed unused env var
   - **alertmanager-discord**: NEW service added

### Documentation

1. **docs/post-commit-steps.md**
   - Updated Discord alerts section
   - Marked as completed with new architecture

2. **DEPLOYMENT_NOTES.md**
   - NEW file documenting this deployment

---

## Deployment Impact

### Downtime
- **Traefik restart:** ~5 seconds (all web services briefly unavailable)
- **AdGuard restart:** ~3 seconds (DNS queries may have failed)
- **Syncthing restart:** ~3 seconds (file sync paused)
- **New service start:** No downtime

### Resource Usage
- **New container:** alertmanager-discord (~10MB RAM, minimal CPU)
- **Traefik:** Upgraded image (~50MB larger)
- **Total additional memory:** ~15MB

### Breaking Changes
- ✅ None - all changes backward compatible

---

## Verification Steps

### 1. All Services Running
```bash
docker compose ps
# Expected: 38/38 containers running (37 + new alertmanager-discord)
```

### 2. Web Services Accessible
```bash
curl -I https://homepage.antoineglacet.com
curl -I https://grafana.antoineglacet.com
# Expected: HTTP 302 (redirect to Authentik) or HTTP 200
```

### 3. Prometheus Targets Healthy
```bash
curl -s http://localhost:9090/api/v1/targets | grep -c '"health":"up"'
# Expected: 5 (prometheus, node_exporter, cadvisor, traefik, loki)
```

### 4. Discord Alerts Working
```bash
# Send test alert
cat << 'EOF' | curl -X POST -H "Content-Type: application/json" -d @- http://localhost:9093/api/v2/alerts
[{"labels":{"alertname":"Test","severity":"info"},"annotations":{"summary":"Test"}}]
EOF

# Check bridge received it
docker compose logs alertmanager-discord --tail=5
# Expected: "alertmanager-discord:9094 - [POST]"
```

### 5. Grafana Datasources
Visit: http://localhost:3000 → Configuration → Data Sources
- ✅ Prometheus (green)
- ✅ Loki (green)

---

## Post-Deployment Monitoring

### First 24 Hours
Monitor these metrics:
- Swap usage trending down (target: <500MB)
- Container memory within limits
- No OOM kills
- Discord alerts delivering
- All Prometheus targets UP

### Key Dashboards
- Node Exporter Full (ID: 1860) - System metrics
- Docker Container Metrics (ID: 179) - Resource usage
- Traefik (ID: 12250) - HTTP traffic
- Loki Logs (ID: 12611) - Container logs

---

## Rollback Procedure

If issues arise:

```bash
# Option 1: Revert this commit only
git revert HEAD
docker compose pull
docker compose up -d

# Option 2: Revert to before monitoring changes
git reset --hard <previous-commit-hash>
docker compose pull  
docker compose up -d
```

**Note:** Reverting will:
- Restore Traefik v3.2 (breaks web access - not recommended)
- Restore AdGuard/Syncthing pinned versions (breaks those services)
- Remove Discord alerting
- Break Prometheus monitoring

**Recommendation:** Fix forward, not rollback

---

## Known Issues

### 1. Traefik Metrics Endpoint
- Configured for port 8082 but metrics only available on 8080 (API port)
- Works but not ideal for security
- TODO: Fix metrics entrypoint configuration

### 2. Alertmanager-Discord Logging
- Bridge logs minimal info (only "[POST]" messages)
- Success/failure not explicitly logged
- Verified working via Discord channel

### 3. Image Versions
- Traefik, AdGuard, Syncthing now on `:latest`
- May auto-upgrade on `docker compose pull`
- Consider pinning to specific versions after stability confirmed

---

## Success Criteria

After 24 hours, verify:

- ✅ All 38 containers running healthy
- ✅ Swap usage <500MB (down from 1.9GB)
- ✅ All web services accessible
- ✅ All Prometheus targets UP
- ✅ Discord receiving real alerts (if any)
- ✅ Grafana showing data
- ✅ No OOM kills
- ✅ SSH sessions responsive

---

## Next Steps

1. **Monitor for 24 hours** - Watch for any regressions
2. **Import Grafana dashboards** - IDs: 1860, 179, 12250, 12611
3. **Tune alert thresholds** - Based on observed metrics
4. **Consider version pinning** - Pin Traefik/AdGuard/Syncthing after testing
5. **Fix Traefik metrics port** - Dedicated metrics endpoint on 8082

---

## Lessons Learned

1. **Version pinning risks:** Always test pinned versions for compatibility
2. **Docker API changes:** Traefik containers must support current Docker API
3. **Config schema versions:** Check compatibility when downgrading image versions
4. **Discord webhooks:** Slack-compatible mode doesn't work with all tools
5. **Network modes:** `host` network requires special Prometheus configuration

---

**Deployment Date:** 2026-01-16
**Services Affected:** Traefik, AdGuard, Syncthing, Alertmanager, Prometheus
**New Services:** alertmanager-discord
**Downtime:** <1 minute
**Status:** ✅ **SUCCESSFUL**
