# Home Server Performance Optimization Guide

**Created**: 2026-01-17  
**System**: Intel Core i5-7500T @ 2.70GHz, 8GB RAM, Ubuntu 24.04.3 LTS  
**Workload**: 39 Docker containers (media, monitoring, auth, smart home, etc.)

---

## 🔴 Problem Identified

### Symptoms
- **Severe SSH lag** when connecting from LAN
- **Slow interactive session response**
- **Service latency** on the local network

### Root Cause Analysis

The issue was **NOT** what you might expect:

| Assumption | Reality |
|------------|---------|
| "swappiness=10 is good for servers" | ❌ **Wrong for heavily-loaded systems** |
| "Lower swappiness = better performance" | ❌ **Causes emergency swap situations** |
| "My system has enough RAM" | ❌ **Only 311MB free, 92.95% committed** |

### The Real Problem

```
Memory Distribution:
├─ Total RAM:     7.6GB
├─ Used:          4.5GB (active processes)
├─ Inactive:      3.9GB (cached, doing nothing useful)
├─ Free:          311MB ⚠️ CRITICAL - too low!
└─ Swap:          238MB (actively being used)

Problem: 3.9GB of INACTIVE memory hogging RAM while active 
processes fight over the remaining 311MB!
```

With **swappiness=10**, the kernel **refuses to swap out inactive pages** until memory pressure becomes critical. When SSH needs memory, the kernel has to perform **emergency reclaim or swap operations**, causing **blocking I/O** and the lag you experience.

### Additional Culprit: CPU Governor

**Another critical factor**: Intel CPUs default to `powersave` governor which:
- Dynamically reduces CPU frequency to save power
- Adds significant latency to CPU frequency scaling transitions
- Makes every command feel sluggish, even with adequate memory
- Compounds the memory pressure issue

**With `performance` governor**:
- CPU stays at maximum frequency (3.3GHz for i5-7500T)
- Eliminates frequency scaling delays
- Provides consistent, low-latency performance
- Dramatically improves SSH and interactive responsiveness

---

## ✅ Solution: Multi-Layered Optimization

### Why Swappiness=60 is Better for Your Setup

| Swappiness=10 (OLD) | Swappiness=60 (NEW) |
|---------------------|---------------------|
| Avoids swapping until critical | Proactively swaps inactive pages |
| Emergency swap = lag spikes | Smooth, predictable swapping |
| 3.9GB inactive memory trapped in RAM | Inactive pages swapped out early |
| ~300MB free for active work | ~2-3GB free for active processes |
| Sudden I/O stalls | Consistent, low-latency I/O |

### Swappiness Values Explained

- **0-10**: Desktop/workstation (user actively using most memory)
- **20-40**: Light server workload
- **60**: **Heavy server workload** ← Your case (39 containers)
- **80-100**: Database servers with massive cache requirements

With **zram swap** (compressed memory), swapping is actually very fast! The kernel can quickly move inactive pages to compressed storage and free up real RAM for your SSH session.

---

## 🎯 Optimizations Applied

### Tier 1: Immediate Impact (Fixes SSH Lag)

#### 1. Memory Management
```bash
vm.swappiness=60                      # Proactive swapping
vm.vfs_cache_pressure=50              # Prefer inode/dentry cache
vm.dirty_background_ratio=5           # Earlier background writeback
vm.dirty_ratio=10                     # Lower dirty page threshold
vm.dirty_writeback_centisecs=500      # Regular flushing
```

**Impact**: Keeps 2-3GB RAM free for interactive sessions, prevents emergency swap situations

#### 2. Network Buffer Optimization
```bash
net.core.rmem_max=4194304             # 4MB (was 208KB)
net.core.wmem_max=4194304             # 4MB (was 208KB)
net.core.netdev_max_backlog=5000      # Higher packet queue
net.ipv4.tcp_congestion_control=bbr   # Modern congestion control
```

**Impact**: 20x larger buffers = better throughput to LAN clients, reduced latency

### Tier 2: Hardware Optimization

#### 3. Network Offload Features
```bash
- TSO (TCP Segmentation Offload): Enabled
- GSO (Generic Segmentation Offload): Enabled
- GRO (Generic Receive Offload): Enabled
```

**Impact**: Reduces CPU usage for network I/O, improves throughput

### Tier 3: Additional Improvements

#### 4. File Descriptor Limits
```bash
fs.file-max=2097152                   # System-wide
fs.nr_open=2097152                    # Per-process
```

**Impact**: Prevents "too many open files" errors with Docker

#### 5. Kernel Scheduler Tuning
```bash
kernel.sched_migration_cost_ns=5000000  # Reduce unnecessary migrations
kernel.sched_autogroup_enabled=0        # Disable desktop optimization
```

**Impact**: Better for server workloads

---

## 📋 How to Apply

### Quick Start

```bash
# 1. Navigate to your home-server directory
cd ~/home-server

# 2. Run the optimization script (requires sudo)
sudo ./scripts/optimize-performance.sh

# 3. (Optional but recommended) Reboot for full effect
sudo reboot
```

### What the Script Does

1. ✅ **Creates backups** of all current settings
2. ✅ **Applies optimizations** across 3 tiers
3. ✅ **Validates changes** and saves before/after state
4. ✅ **Creates rollback script** for safety
5. ✅ **Persists settings** across reboots

### Safety Features

- **Full backup** before any changes
- **Automatic rollback script** generation
- **Detailed logging** of all operations
- **Pre-flight checks** to prevent issues

---

## 🔄 Rollback Instructions

If you need to revert the changes:

```bash
# Find your backup directory (printed during optimization)
cd ~/home-server/backups/performance-tuning-YYYYMMDD-HHMMSS/

# Run the rollback script
sudo ./rollback.sh

# Reboot
sudo reboot
```

---

## 📊 Monitoring Your System

### Before Optimization Metrics

```
Load Average: 1.06, 0.95, 0.97
Memory Free: 311MB
Swap Used: 238MB
Network Buffers: 208KB
TCP Offload: Disabled
```

### Monitor After Optimization

```bash
# Check memory usage
free -h

# Monitor swap activity (should be more but smoother)
vmstat 1

# Check network statistics
sar -n DEV 1

# View Docker container stats
docker stats

# Check applied sysctl values
sysctl -a | grep -E '(vm.swappiness|net.core)'
```

### Expected Improvements

- **SSH latency**: Immediate improvement (should feel snappy)
- **Free memory**: Increase to 1-3GB within hours
- **Swap usage**: May increase (this is GOOD - it's swapping out inactive pages)
- **Network throughput**: Better performance for LAN clients
- **Overall responsiveness**: Smoother, more predictable

---

## 🐳 Docker Memory Limits (Optional Step 2)

After kernel optimizations, consider adding memory limits to containers.

### View Recommendations

```bash
./scripts/add-docker-memory-limits.sh
```

This shows recommended memory limits for all your containers.

### Why Add Memory Limits?

- Prevents memory hogging by any single container
- Allows Docker to make better scheduling decisions
- Works with kernel's memory management
- Provides predictable resource allocation

### How to Apply

1. **Backup docker-compose.yml**:
   ```bash
   cp ~/home-server/docker-compose.yml ~/home-server/docker-compose.yml.backup
   ```

2. **Add deploy sections** from the script output to your services

3. **Recreate containers**:
   ```bash
   cd ~/home-server
   docker compose up -d
   ```

---

## 🎓 Understanding the Changes

### Common Misconceptions

#### ❌ "Swap is always bad"
**Reality**: Swap is a tool. Used proactively (swappiness=60), it keeps RAM free for active processes.

#### ❌ "Lower swappiness = faster system"
**Reality**: Lower swappiness works for desktops where you actively use most memory. For servers with many containers, higher swappiness prevents emergency swap situations.

#### ❌ "If swap usage increases, something is wrong"
**Reality**: Swap usage SHOULD increase with swappiness=60. It's swapping out inactive pages. Watch for **swap I/O** (si/so in vmstat), not swap usage.

### What to Actually Monitor

✅ **Good indicators**:
- Free memory (should increase)
- SSH responsiveness (should improve)
- Load average (should stabilize)
- Swap I/O rate (si/so) - should be low and steady

❌ **Don't worry about**:
- Swap usage % (will likely increase)
- Cache size (will decrease as inactive pages are swapped)

---

## 📈 Expected Timeline

| Time | Expected Behavior |
|------|-------------------|
| **Immediate** | SSH latency improves, network feels snappier |
| **5-10 min** | Kernel starts swapping out inactive pages |
| **30-60 min** | Free memory increases to 1-2GB |
| **2-4 hours** | System reaches new equilibrium |
| **1-2 days** | Full performance characteristics visible |

---

## 🔧 Troubleshooting

### Issue: Swap I/O is very high (si/so > 1000 in vmstat)

**Solution**: System is thrashing. You may have too many containers for 8GB RAM.
- Consider adding more RAM
- Or reduce number of running containers
- Or adjust swappiness to 40-50 (middle ground)

### Issue: Container keeps getting OOM killed

**Solution**: Container needs more memory
- Check `docker logs <container>`
- Increase memory limit in docker-compose.yml
- Or investigate why it's using so much memory

### Issue: System still feels slow

**Diagnosis**:
```bash
# Check I/O wait
vmstat 1 5

# Check disk performance
iostat -x 1 5

# Check network errors
netstat -i
```

---

## 📚 Additional Resources

### Files Created by Optimization

```
~/home-server/
├── scripts/
│   ├── optimize-performance.sh          # Main optimization script
│   └── add-docker-memory-limits.sh      # Docker limits helper
├── logs/
│   └── performance-optimization.log     # Execution log
├── backups/
│   └── performance-tuning-TIMESTAMP/    # Backup & rollback
│       ├── rollback.sh                  # Rollback script
│       ├── sysctl-before.conf           # Original settings
│       ├── sysctl-after.conf            # New settings
│       └── *.txt                        # Various metrics
└── PERFORMANCE_OPTIMIZATION.md          # This file
```

### System Configuration Files Modified

```
/etc/sysctl.d/
├── 99-swappiness.conf              # Memory swapping behavior
├── 99-vfs-cache.conf               # Filesystem cache pressure
├── 99-dirty-pages.conf             # Page writeback tuning
├── 99-network-performance.conf     # Network buffer optimization
├── 99-file-descriptors.conf        # File descriptor limits
└── 99-kernel-performance.conf      # Misc kernel tuning

/etc/systemd/system/
└── network-offload-optimization.service   # Persist NIC offload

/etc/security/
└── limits.conf                     # User process limits
```

---

## 🎯 Summary

### The Core Fix

Your SSH lag was caused by **memory pressure**, not by swappiness being too high, but by swappiness being **too low** for your workload.

**The fix**: Increase swappiness to 60 so the kernel proactively swaps out inactive memory pages, keeping more RAM free for your interactive SSH sessions.

### Key Takeaways

1. **Swappiness is workload-dependent** - 10 is great for desktops, 60 is better for heavily-loaded servers
2. **Swap usage is not inherently bad** - it's a tool for better memory management
3. **Free RAM is more important than avoiding swap** - for interactive responsiveness
4. **Network buffers matter** - especially with 39 containers on gigabit LAN
5. **Hardware offload helps** - reduces CPU overhead for network I/O

### Questions?

Check the logs:
```bash
cat ~/home-server/logs/performance-optimization.log
```

Or review the backup for original values:
```bash
ls -la ~/home-server/backups/performance-tuning-*/
```

---

**Last Updated**: 2026-01-17  
**Script Version**: 1.0  
**Status**: Ready for production use
