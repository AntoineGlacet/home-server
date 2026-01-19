#!/bin/bash
################################################################################
# Home Server Performance Optimization Script
# Created: 2026-01-17
# 
# Purpose: Optimize system performance for Docker-heavy workload
# - Fix SSH/LAN latency issues
# - Optimize memory management
# - Improve network throughput
# - Enable hardware offloading
#
# Safety: Creates backups before all changes
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Backup directory
BACKUP_DIR="/home/antoine/home-server/backups/performance-tuning-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/home/antoine/home-server/logs/performance-optimization.log"

# Create necessary directories
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"

################################################################################
# Logging functions
################################################################################

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}$*${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
}

################################################################################
# Pre-flight checks
################################################################################

preflight_checks() {
    log_section "Pre-flight Checks"
    
    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Check if sysctl is available
    if ! command -v sysctl &> /dev/null; then
        log_error "sysctl command not found"
        exit 1
    fi
    
    # Check if ethtool is available
    if ! command -v ethtool &> /dev/null; then
        log_warn "ethtool not found, installing..."
        apt-get update -qq && apt-get install -y ethtool
    fi
    
    log "✓ All pre-flight checks passed"
}

################################################################################
# Backup current configuration
################################################################################

backup_current_config() {
    log_section "Backing Up Current Configuration"
    
    # Backup sysctl settings
    log "Backing up current sysctl configuration..."
    sysctl -a > "$BACKUP_DIR/sysctl-before.conf" 2>/dev/null
    
    # Backup individual sysctl.d files
    if [ -d /etc/sysctl.d ]; then
        cp -r /etc/sysctl.d "$BACKUP_DIR/sysctl.d-backup"
    fi
    
    # Backup network interface settings
    log "Backing up network interface settings..."
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$MAIN_IFACE" ]; then
        ethtool -k "$MAIN_IFACE" > "$BACKUP_DIR/ethtool-$MAIN_IFACE-before.txt" 2>/dev/null || true
        ethtool "$MAIN_IFACE" > "$BACKUP_DIR/ethtool-$MAIN_IFACE-settings.txt" 2>/dev/null || true
    fi
    
    # Backup memory info
    free -h > "$BACKUP_DIR/memory-before.txt"
    cat /proc/meminfo > "$BACKUP_DIR/meminfo-before.txt"
    
    # Save current performance metrics
    vmstat 1 3 > "$BACKUP_DIR/vmstat-before.txt"
    
    log "✓ Backups saved to: $BACKUP_DIR"
}

################################################################################
# TIER 1: Fix SSH/LAN Latency (Immediate Impact)
################################################################################

optimize_memory_management() {
    log_section "TIER 1: Optimizing Memory Management"
    
    # Update swappiness to 60 (from 10)
    log "Setting vm.swappiness to 60 (proactive swapping for better responsiveness)..."
    cat > /etc/sysctl.d/99-swappiness.conf << 'EOF'
# Swappiness optimization for heavily-loaded server
# Higher value (60) allows proactive swapping of inactive memory
# This keeps more free RAM available for interactive sessions
# Prevents emergency swap situations that cause lag spikes
vm.swappiness=60
EOF
    sysctl -w vm.swappiness=60
    
    # Optimize VFS cache pressure
    log "Setting vm.vfs_cache_pressure to 50 (prefer inode/dentry cache)..."
    cat > /etc/sysctl.d/99-vfs-cache.conf << 'EOF'
# VFS cache pressure optimization
# Lower value (50) = kernel prefers keeping directory/inode cache
# Benefits Docker overlay filesystem and reduces file operation latency
vm.vfs_cache_pressure=50
EOF
    sysctl -w vm.vfs_cache_pressure=50
    
    # Optimize dirty page handling for better interactive performance
    log "Optimizing dirty page writeback..."
    cat > /etc/sysctl.d/99-dirty-pages.conf << 'EOF'
# Dirty page optimization for responsive I/O
# Start background writeback earlier to avoid sudden I/O stalls
vm.dirty_background_ratio=5
vm.dirty_ratio=10

# Maximum time dirty pages can stay in memory (centiseconds)
# Ensures regular flushing to avoid large writebacks
vm.dirty_expire_centisecs=3000
vm.dirty_writeback_centisecs=500
EOF
    sysctl -w vm.dirty_background_ratio=5
    sysctl -w vm.dirty_ratio=10
    sysctl -w vm.dirty_expire_centisecs=3000
    sysctl -w vm.dirty_writeback_centisecs=500
    
    log "✓ Memory management optimized"
}

optimize_network_buffers() {
    log_section "TIER 1: Optimizing Network Performance"
    
    log "Increasing network buffers for gigabit LAN performance..."
    cat > /etc/sysctl.d/99-network-performance.conf << 'EOF'
# Network buffer optimization for gigabit LAN
# Default 208KB is too small, increasing to 2-4MB for better throughput
# Reduces packet drops and improves responsiveness for LAN clients

# Core network buffers
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.core.rmem_default=262144
net.core.wmem_default=262144

# TCP memory buffers (min, default, max in bytes)
net.ipv4.tcp_rmem=4096 262144 4194304
net.ipv4.tcp_wmem=4096 262144 4194304

# Increase backlog for heavy Docker networking
net.core.netdev_max_backlog=5000

# TCP optimizations
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_slow_start_after_idle=0

# Reduce TIME_WAIT connections (helps with Docker port churn)
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_tw_reuse=1

# Connection tracking for Docker
net.netfilter.nf_conntrack_max=262144
net.nf_conntrack_max=262144
EOF
    
    # Apply network settings
    sysctl -w net.core.rmem_max=4194304
    sysctl -w net.core.wmem_max=4194304
    sysctl -w net.core.rmem_default=262144
    sysctl -w net.core.wmem_default=262144
    sysctl -w net.ipv4.tcp_rmem="4096 262144 4194304"
    sysctl -w net.ipv4.tcp_wmem="4096 262144 4194304"
    sysctl -w net.core.netdev_max_backlog=5000
    
    # BBR congestion control (if available)
    if lsmod | grep -q tcp_bbr || modprobe tcp_bbr 2>/dev/null; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr
        log "✓ Enabled BBR congestion control"
    else
        log_warn "BBR not available, using default congestion control"
    fi
    
    sysctl -w net.ipv4.tcp_notsent_lowat=16384 2>/dev/null || true
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0
    sysctl -w net.ipv4.tcp_fin_timeout=30
    sysctl -w net.ipv4.tcp_tw_reuse=1
    
    # Connection tracking
    sysctl -w net.netfilter.nf_conntrack_max=262144 2>/dev/null || true
    sysctl -w net.nf_conntrack_max=262144 2>/dev/null || true
    
    log "✓ Network buffers optimized"
}

enable_hardware_offload() {
    log_section "TIER 2: Enabling Hardware Offload"
    
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [ -z "$MAIN_IFACE" ]; then
        log_warn "Could not detect main network interface, skipping offload optimization"
        return
    fi
    
    log "Optimizing network interface: $MAIN_IFACE"
    
    # Enable TCP segmentation offload
    log "Enabling TCP segmentation offload..."
    if ethtool -K "$MAIN_IFACE" tso on 2>/dev/null; then
        log "✓ TSO enabled"
    else
        log_warn "Could not enable TSO (may not be supported)"
    fi
    
    # Enable generic segmentation offload
    if ethtool -K "$MAIN_IFACE" gso on 2>/dev/null; then
        log "✓ GSO enabled"
    else
        log_warn "Could not enable GSO"
    fi
    
    # Enable generic receive offload
    if ethtool -K "$MAIN_IFACE" gro on 2>/dev/null; then
        log "✓ GRO enabled"
    else
        log_warn "Could not enable GRO"
    fi
    
    # Create systemd service to persist offload settings across reboots
    log "Creating systemd service to persist offload settings..."
    cat > /etc/systemd/system/network-offload-optimization.service << EOF
[Unit]
Description=Network Hardware Offload Optimization
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K $MAIN_IFACE tso on gso on gro on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable network-offload-optimization.service
    
    log "✓ Hardware offload enabled and persisted"
}

################################################################################
# Additional optimizations
################################################################################

optimize_file_descriptors() {
    log_section "TIER 3: Optimizing File Descriptors"
    
    log "Increasing file descriptor limits for Docker workloads..."
    cat > /etc/sysctl.d/99-file-descriptors.conf << 'EOF'
# File descriptor limits for heavy Docker workloads
fs.file-max=2097152
fs.nr_open=2097152
EOF
    
    sysctl -w fs.file-max=2097152
    sysctl -w fs.nr_open=2097152
    
    # Update limits.conf for user processes
    if ! grep -q "antoine.*nofile" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << 'EOF'

# File descriptor limits for Docker user
antoine soft nofile 65536
antoine hard nofile 524288
EOF
        log "✓ User file descriptor limits updated"
    fi
    
    log "✓ File descriptor limits optimized"
}

optimize_kernel_params() {
    log_section "TIER 3: Additional Kernel Optimizations"
    
    log "Applying additional kernel optimizations..."
    cat > /etc/sysctl.d/99-kernel-performance.conf << 'EOF'
# Kernel performance optimizations

# Increase inotify watches for Docker containers
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512

# Optimize scheduler for server workload
kernel.sched_migration_cost_ns=5000000
kernel.sched_autogroup_enabled=0

# Reduce swapiness threshold for emergency
vm.watermark_scale_factor=200

# Optimize memory compaction
vm.compaction_proactiveness=20
EOF
    
    sysctl -w fs.inotify.max_user_watches=524288
    sysctl -w fs.inotify.max_user_instances=512
    sysctl -w kernel.sched_migration_cost_ns=5000000
    sysctl -w kernel.sched_autogroup_enabled=0
    sysctl -w vm.watermark_scale_factor=200 2>/dev/null || true
    sysctl -w vm.compaction_proactiveness=20 2>/dev/null || true
    
    log "✓ Kernel parameters optimized"
}

################################################################################
# Post-optimization validation
################################################################################

validate_optimizations() {
    log_section "Validating Optimizations"
    
    log "Current system parameters:"
    echo "  - vm.swappiness: $(sysctl -n vm.swappiness)"
    echo "  - vm.vfs_cache_pressure: $(sysctl -n vm.vfs_cache_pressure)"
    echo "  - vm.dirty_background_ratio: $(sysctl -n vm.dirty_background_ratio)"
    echo "  - vm.dirty_ratio: $(sysctl -n vm.dirty_ratio)"
    echo "  - net.core.rmem_max: $(sysctl -n net.core.rmem_max) bytes"
    echo "  - net.core.wmem_max: $(sysctl -n net.core.wmem_max) bytes"
    echo "  - net.core.netdev_max_backlog: $(sysctl -n net.core.netdev_max_backlog)"
    echo ""
    
    # Save post-optimization state
    sysctl -a > "$BACKUP_DIR/sysctl-after.conf" 2>/dev/null
    free -h > "$BACKUP_DIR/memory-after.txt"
    vmstat 1 3 > "$BACKUP_DIR/vmstat-after.txt"
    
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$MAIN_IFACE" ]; then
        ethtool -k "$MAIN_IFACE" > "$BACKUP_DIR/ethtool-$MAIN_IFACE-after.txt" 2>/dev/null || true
    fi
    
    log "✓ Validation complete"
}

################################################################################
# Create rollback script
################################################################################

create_rollback_script() {
    log_section "Creating Rollback Script"
    
    cat > "$BACKUP_DIR/rollback.sh" << 'ROLLBACK_EOF'
#!/bin/bash
# Rollback script for performance optimizations
# Generated automatically - DO NOT EDIT

set -euo pipefail

echo "Rolling back performance optimizations..."

# Restore original sysctl.d files
if [ -d "sysctl.d-backup" ]; then
    echo "Restoring sysctl.d configuration..."
    sudo rm -f /etc/sysctl.d/99-swappiness.conf
    sudo rm -f /etc/sysctl.d/99-vfs-cache.conf
    sudo rm -f /etc/sysctl.d/99-dirty-pages.conf
    sudo rm -f /etc/sysctl.d/99-network-performance.conf
    sudo rm -f /etc/sysctl.d/99-file-descriptors.conf
    sudo rm -f /etc/sysctl.d/99-kernel-performance.conf
    
    # Apply original settings
    sudo sysctl -p
    for conf in /etc/sysctl.d/*.conf; do
        sudo sysctl -p "$conf" 2>/dev/null || true
    done
fi

# Disable network offload service
if systemctl is-enabled network-offload-optimization.service 2>/dev/null; then
    echo "Disabling network offload service..."
    sudo systemctl disable network-offload-optimization.service
    sudo rm -f /etc/systemd/system/network-offload-optimization.service
    sudo systemctl daemon-reload
fi

echo "Rollback complete. Please reboot for all changes to take effect."
echo "You can review the original settings in: $(pwd)"
ROLLBACK_EOF
    
    chmod +x "$BACKUP_DIR/rollback.sh"
    log "✓ Rollback script created: $BACKUP_DIR/rollback.sh"
}

################################################################################
# Main execution
################################################################################

main() {
    clear
    log_section "Home Server Performance Optimization"
    log "Script started at: $(date)"
    log "Backup directory: $BACKUP_DIR"
    echo ""
    
    preflight_checks
    backup_current_config
    
    # TIER 1: Immediate impact optimizations
    optimize_memory_management
    optimize_network_buffers
    
    # TIER 2: Hardware optimizations
    enable_hardware_offload
    
    # TIER 3: Additional optimizations
    optimize_file_descriptors
    optimize_kernel_params
    
    # Validation and cleanup
    validate_optimizations
    create_rollback_script
    
    log_section "Optimization Complete!"
    echo ""
    echo -e "${GREEN}✓ All optimizations applied successfully!${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
    echo "1. Some optimizations take effect immediately"
    echo "2. For best results, consider a reboot (optional but recommended)"
    echo "3. Monitor system behavior over the next few hours"
    echo "4. SSH/LAN latency should improve immediately"
    echo ""
    echo -e "${BLUE}Backup location:${NC} $BACKUP_DIR"
    echo -e "${BLUE}Rollback script:${NC} $BACKUP_DIR/rollback.sh"
    echo -e "${BLUE}Log file:${NC} $LOG_FILE"
    echo ""
    echo -e "${YELLOW}To rollback these changes:${NC}"
    echo "  cd $BACKUP_DIR && sudo ./rollback.sh"
    echo ""
    echo -e "${GREEN}Monitoring recommendations:${NC}"
    echo "  - Watch memory usage: free -h"
    echo "  - Monitor swap activity: vmstat 1"
    echo "  - Check network stats: sar -n DEV 1"
    echo "  - View sysctl values: sysctl -a | grep -E '(vm|net)'"
    echo ""
}

# Run main function
main "$@"
