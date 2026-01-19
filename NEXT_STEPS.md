# Next Steps - Alerting Migration Testing

**Status**: ✅ Backend provisioning complete - Frontend testing required

---

## 🎯 What You Need to Do

All automated setup is complete. You just need to verify the alerts work through the Grafana UI.

### 1. Access Grafana (Required)
Open your browser and go to:
```
https://grafana.antoineglacet.com
```

### 2. Test Discord Contact Point (Required)
1. Click **Alerting** in the left sidebar (bell icon)
2. Click **Contact points**
3. You should see `discord` in the list
4. Click the **Test** button next to it
5. **Check your Discord** - you should receive a test message

Expected Discord message:
```
[FIRING:1]  
(test notification from Grafana)
```

If you see this message in Discord: **✅ Success!** The migration is complete.

### 3. Verify Alert Rules (Optional but Recommended)
1. In Grafana, click **Alerting** → **Alert rules**
2. You should see **23 alert rules** across these folders:
   - System (6 performance alerts - NEW!)
   - System (memory alerts)
   - System (disk alerts)
   - Containers (10 alerts)
   - Services (4 alerts)

### 4. Trigger Test Alert (Optional)
Want to see a real alert in action?

```bash
# Temporarily switch CPU governor to trigger alert
sudo cpupower frequency-set -g powersave

# Wait 1 minute - you should receive Discord alert:
# "CPU governor not in performance mode"

# Switch back
sudo cpupower frequency-set -g performance
```

---

## 🔍 Troubleshooting

### Discord test fails
**Check 1**: Verify webhook URL is set
```bash
cd ~/home-server
docker exec grafana env | grep DISCORD_WEBHOOK_URL
```

Should output: `DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...`

**Check 2**: Test webhook directly
```bash
curl -X POST "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "Direct test from command line"}'
```

If this works but Grafana test doesn't, restart Grafana:
```bash
docker restart grafana
```

### Don't see 23 alert rules
**Check**: Grafana logs for errors
```bash
docker logs grafana 2>&1 | grep -i "error" | tail -20
```

The template errors you see are **normal and expected** - they occur when alerts haven't fired yet.

### Can't access Grafana UI
**Check**: Traefik and Authentik are running
```bash
docker ps --filter "name=traefik" --filter "name=authentik"
```

Try direct access without Traefik:
```bash
# From your server
curl http://localhost:3000/api/health

# Should return: {"database":"ok","version":"..."}
```

---

## ✅ Success Criteria

You're done when:
1. ✅ Discord test message received
2. ✅ 23 alert rules visible in Grafana
3. ✅ No errors in Grafana logs (template errors are OK)

---

## 📊 What Changed

**Removed**:
- `alertmanager` container
- `alertmanager-discord` container
- Alertmanager config in Prometheus

**Added**:
- Grafana Unified Alerting (built-in)
- Native Discord integration
- 6 new performance alerts (prevent SSH lag)
- All configuration as code (YAML provisioning)

**Result**: 
- 2 fewer containers
- Simpler architecture
- Same functionality
- Better performance monitoring

---

## 📚 More Info

For complete details, see: `ALERTING_MIGRATION.md`

For performance optimization details, see: `PERFORMANCE_OPTIMIZATION.md`

---

**Created**: 2026-01-17
**Grafana URL**: https://grafana.antoineglacet.com
**Status**: Waiting for user testing
