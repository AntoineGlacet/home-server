---
title: "Performance Tuning Guide"
weight: 2
description: "Performance optimizations for the Dell OptiPlex 3050 home server running 37+ Docker containers"
---

This guide covers performance optimizations for the Dell OptiPlex 3050 home server running 37+ Docker containers.

## System Specifications

- **CPU:** Intel Core i5-7500T (4 cores @ 2.70GHz)
- **RAM:** 8GB DDR4
- **Storage:** 98GB system drive + 5.5TB data drive
- **OS:** Ubuntu 24.04.3 LTS

## Critical Issue: Swap Thrashing

### Problem

With the default Ubuntu swappiness setting of `60`, the system aggressively swaps memory to disk even when there's available RAM. This causes:

- **Slow interactive SSH sessions** - Commands take seconds to respond
- **High disk I/O** - Constant swap read/write activity
- **Degraded container performance** - Services become sluggish
- **Poor responsiveness** - Desktop/terminal feels frozen

### Why This Happens

**Swappiness** is a Linux kernel parameter that controls how aggressively the system swaps memory pages to disk:
- **Value 0-10:** Minimize swapping, use RAM as much as possible
- **Value 60 (default):** Balance between RAM and swap usage
- **Value 100:** Swap aggressively to keep RAM free

On desktop/server workloads with 8GB RAM, the default `60` is **too high** because:
1. The kernel preemptively swaps out inactive pages to "free up" RAM
2. When you interact with a swapped process, it causes disk I/O delays
3. File-based swap (`/swap.img`) is slower than physical swap partitions
4. Docker containers generate memory pressure that triggers excessive swapping

### Current State Analysis

Check your current swap usage:
```bash
# View swap configuration
swapon --show
# Output: NAME      TYPE SIZE USED PRIO
#         /swap.img file   4G 1.9G   -2

# Check swappiness value
cat /proc/sys/vm/swappiness
# Output: 60

# View memory and swap usage
free -h
#               total        used        free      shared  buff/cache   available
# Mem:           7.6Gi       4.0Gi       303Mi       128Mi       3.8Gi       3.7Gi
# Swap:          4.0Gi       1.9Gi       2.1Gi
```

**Notice:** 1.9GB of swap used despite having 3.7GB available RAM!

## Solution: Reduce Swappiness to 10

### Temporary Change (Testing)

Apply immediately without reboot:
```bash
# Reduce swappiness from 60 to 10
sudo sysctl vm.swappiness=10

# Verify the change
cat /proc/sys/vm/swappiness
# Output: 10
```

### Permanent Change (Recommended)

Make it survive reboots:
```bash
# Add to sysctl configuration
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

# Or create a dedicated config file (preferred)
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf

# Apply immediately
sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
```

### Optional: Clear Swap (If Safe)

If your system has free RAM, you can clear the swap cache:
```bash
# Only do this if you have enough free RAM!
# Check free RAM first
free -h

# If you have >4GB free, temporarily disable and re-enable swap
sudo swapoff -a && sudo swapon -a

# Verify swap usage is reduced
free -h
```

⚠️ **Warning:** Do NOT disable swap on a production system during high load!

## Expected Results

After reducing swappiness to 10:

- ✅ **Faster SSH sessions** - Commands respond instantly
- ✅ **Lower disk I/O** - Swap only used when RAM is actually full
- ✅ **Better container performance** - Services run in RAM, not disk
- ✅ **Reduced swap usage** - Should drop to <500MB under normal load

### Monitoring the Impact

Track swap usage over time:
```bash
# Watch swap usage in real-time
watch -n 1 'free -h | grep -E "Mem|Swap"'

# Check disk I/O (look for low wa% after tuning)
iostat -x 5

# Monitor with Prometheus/Grafana
# Metrics: node_memory_SwapTotal_bytes, node_memory_SwapFree_bytes
```

## Additional Performance Optimizations

### 1. Container Resource Limits

Prevent memory exhaustion by limiting top consumers (see docker-compose.yml):
```yaml
deploy:
  resources:
    limits:
      memory: 768M  # Prevent container from using all RAM
    reservations:
      memory: 256M  # Guaranteed minimum allocation
```

**Top memory consumers (pre-limits):**
- `authentik-server`: 535MB → Limit to 768MB
- `radarr`: 289MB → Limit to 512MB
- `sonarr`: 194MB → Limit to 384MB
- `flaresolverr`: 174MB → Limit to 256MB

### 2. Disk I/O Optimization

#### Enable noatime for Data Drive

Reduce disk writes by not updating access times:
```bash
# Check current mount options
mount | grep /media/data

# Add noatime to /etc/fstab
sudo nano /etc/fstab
# Change: /dev/sdb1  /media/data  ext4  defaults  0  2
# To:     /dev/sdb1  /media/data  ext4  defaults,noatime  0  2

# Remount with new options
sudo mount -o remount /media/data
```

#### Docker Log Rotation

Prevent containers from filling disk with logs (add to docker-compose.yml):
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### 3. CPU Governor

Ensure CPU runs at full speed under load:
```bash
# Check current governor
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Set to performance mode (optional, increases power usage)
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Or keep ondemand/powersave (default, better for power efficiency)
```

### 4. Swap File Optimization

Current swap is a 4GB file. Consider optimizing it:
```bash
# Check current swap
sudo swapon --show

# Optional: Increase swap to 8GB (match RAM size)
sudo swapoff /swap.img
sudo dd if=/dev/zero of=/swap.img bs=1M count=8192 status=progress
sudo chmod 600 /swap.img
sudo mkswap /swap.img
sudo swapon /swap.img
```

**Note:** With swappiness=10, you may not need more swap.

## Monitoring Performance

### Key Metrics to Track

1. **Swap Usage**
   - Target: <500MB under normal load
   - Alert: >2GB indicates memory pressure

2. **Memory Pressure**
   - Target: >1GB free RAM available
   - Alert: <500MB free RAM

3. **Disk Space**
   - System: <70% used (currently 67%)
   - Data: <90% used (currently 85% ⚠️)

4. **Container Restarts**
   - Target: 0 OOM kills
   - Alert: Any container killed due to memory

### Grafana Dashboard Queries

See the "Home Server Overview" dashboard for:
- Swap usage trend: `node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes`
- Memory pressure: `node_memory_MemAvailable_bytes`
- Disk usage: `node_filesystem_avail_bytes{mountpoint="/"}`

## Troubleshooting

### High Swap Despite Low Swappiness

If swap remains high after setting swappiness=10:
1. Identify memory hogs: `docker stats --no-stream | sort -k7 -h`
2. Check for memory leaks in containers
3. Consider adding more RAM or reducing container limits
4. Use `docker compose restart` to reload containers

### OOM Killer Triggered

If containers are killed due to memory:
```bash
# Check kernel logs
sudo dmesg | grep -i "out of memory"
sudo journalctl -k | grep -i oom

# Identify the victim
docker ps -a | grep -E "Exited|Restarted"
```

**Solution:** Increase memory limits or reduce concurrent containers.

### Slow Performance After Limits

If containers perform poorly after adding limits:
1. Monitor actual usage: `docker stats`
2. Increase limits for legitimate high-memory services
3. Check application logs for memory errors
4. Consider SSD upgrade if disk I/O is bottleneck

## Verification Checklist

After applying optimizations:

- [ ] Swappiness set to 10 (`cat /proc/sys/vm/swappiness`)
- [ ] Permanent config in `/etc/sysctl.d/99-swappiness.conf`
- [ ] Swap usage <500MB during normal operation
- [ ] SSH sessions respond instantly
- [ ] Free RAM >1GB available
- [ ] Grafana dashboard shows swap trend
- [ ] No OOM kills in last 24h (`journalctl -k | grep -i oom`)

## References

- [Linux Kernel Documentation: sysctl/vm.txt](https://www.kernel.org/doc/Documentation/sysctl/vm.txt)
- [Ubuntu Swap FAQ](https://help.ubuntu.com/community/SwapFaq)
- [Docker Resource Constraints](https://docs.docker.com/config/containers/resource_constraints/)
- [Prometheus Node Exporter Metrics](https://github.com/prometheus/node_exporter)

## Need Help?

If performance issues persist after these optimizations:
1. Run `scripts/health-check.sh` to identify bottlenecks
2. Check Grafana dashboards for anomalies
3. Review container logs for errors: `docker compose logs --tail=100`
4. Consider hardware upgrade (RAM → 16GB for future growth)
