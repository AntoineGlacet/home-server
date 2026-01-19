# Quick Start: Fix SSH Lag & LAN Latency

## TL;DR - Just Fix It Now

```bash
cd ~/home-server
sudo ./scripts/optimize-performance.sh
```

That's it! Your SSH lag should improve immediately.

---

## What This Does

✅ Increases swappiness to 60 (proactive memory management)  
✅ Optimizes network buffers (20x larger for gigabit LAN)  
✅ Enables hardware offload (reduces CPU for network I/O)  
✅ Tunes kernel parameters for server workload  
✅ Creates automatic backups and rollback script  

---

## Why Your SSH is Lagging

**Problem**: Only 311MB RAM free with 39 containers running  
**Cause**: Swappiness=10 prevents swapping out 3.9GB of inactive memory  
**Result**: Emergency memory reclaim when SSH needs RAM = lag spikes  

**Solution**: Swappiness=60 swaps out inactive pages early, keeps 2-3GB RAM free

---

## Monitoring After Optimization

### Check if it's working:
```bash
# Memory should have more free
free -h

# Swap activity (watch si/so columns, should be low)
vmstat 1 5

# View new settings
sysctl vm.swappiness
```

### What to expect:
- **Immediate**: SSH feels snappy again
- **30 min**: Free RAM increases to 1-2GB
- **2-4 hrs**: System reaches new equilibrium

---

## Optional: Add Docker Memory Limits

After kernel optimization, consider adding memory limits:

```bash
# View recommendations
./scripts/add-docker-memory-limits.sh

# Backup docker-compose.yml
cp docker-compose.yml docker-compose.yml.backup

# (Then manually add the deploy sections shown)

# Apply changes
docker compose up -d
```

---

## Need to Rollback?

```bash
# Find your backup (timestamp will be different)
cd ~/home-server/backups/performance-tuning-*/

# Run rollback
sudo ./rollback.sh && sudo reboot
```

---

## Files Created

- `~/home-server/scripts/optimize-performance.sh` - Main script
- `~/home-server/scripts/add-docker-memory-limits.sh` - Docker helper
- `~/home-server/PERFORMANCE_OPTIMIZATION.md` - Full documentation
- `~/home-server/logs/performance-optimization.log` - Execution log
- `~/home-server/backups/performance-tuning-*/` - Backups & rollback

---

## Common Misconceptions Debunked

❌ "Lower swappiness = better performance"  
✅ **Reality**: Depends on workload. For 39 containers, higher is better.

❌ "Swap usage means something is wrong"  
✅ **Reality**: Proactive swapping keeps RAM free for active work.

❌ "Swappiness=10 is best for servers"  
✅ **Reality**: Only for lightly-loaded servers. Heavy workloads need 60.

---

## Questions?

Read the full docs:
```bash
cat ~/home-server/PERFORMANCE_OPTIMIZATION.md
```

Check the logs:
```bash
cat ~/home-server/logs/performance-optimization.log
```

---

**Status**: Ready to run  
**Risk Level**: Low (full backups + rollback script included)  
**Expected Improvement**: Immediate SSH responsiveness  
