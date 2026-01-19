#!/bin/bash
################################################################################
# Docker Memory Limits Configuration
# Created: 2026-01-17
# 
# Purpose: Add memory limits to containers that don't have them
# This is a helper script to generate the required docker-compose.yml changes
################################################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Docker Memory Limits Recommendations${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Based on current usage analysis, here are recommended memory limits"
echo "for containers that don't currently have them:"
echo ""

cat << 'EOF'
Add these deploy sections to your docker-compose.yml:

# ==============================================================================
# CORE SERVICES
# ==============================================================================

  home-assistant:
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M

  siyuan:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

# ==============================================================================
# MONITORING & METRICS
# ==============================================================================

  prometheus:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  grafana:
    deploy:
      resources:
        limits:
          memory: 384M
        reservations:
          memory: 192M

  glances:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  uptime-kuma:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

# ==============================================================================
# MEDIA SERVICES
# ==============================================================================

  plex:
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

  overseerr:
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M

  calibre-web-automated:
    deploy:
      resources:
        limits:
          memory: 384M
        reservations:
          memory: 192M

# ==============================================================================
# NETWORK & UTILITIES
# ==============================================================================

  adguard:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  syncthing:
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 64M

  samba:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  homepage:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  duplicati:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

# ==============================================================================
# MQTT & SMART HOME
# ==============================================================================

  mqtt:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

  zigbee2mqtt:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

# ==============================================================================
# VPN & DOWNLOADS
# ==============================================================================

  nordlynx:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

  transmission:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  prowlarr:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

# ==============================================================================
# AUTH & DATABASE
# ==============================================================================

  postgres:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  authentik-redis:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

# ==============================================================================
# REVERSE PROXY & CERTS
# ==============================================================================

  traefik:
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 64M

  traefik-certs-dumper:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

# ==============================================================================
# LOGGING
# ==============================================================================

  loki:
    deploy:
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M

  promtail:
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 64M

# ==============================================================================
# ALERTING
# ==============================================================================

  alertmanager:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

  alertmanager-discord:
    deploy:
      resources:
        limits:
          memory: 32M
        reservations:
          memory: 16M

# ==============================================================================
# UTILITIES
# ==============================================================================

  autoheal:
    deploy:
      resources:
        limits:
          memory: 32M
        reservations:
          memory: 16M

  ddclient:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

  node_exporter:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

  cadvisor:
    deploy:
      resources:
        limits:
          memory: 128M
        reservations:
          memory: 64M

# ==============================================================================
# SELENIUM (FOR MINABOT)
# ==============================================================================

  minabot-selenium-1:
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M

  minabot-python-1:
    deploy:
      resources:
        limits:
          memory: 64M
        reservations:
          memory: 32M

EOF

echo ""
echo -e "${GREEN}MEMORY ALLOCATION SUMMARY:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Current system: 8GB RAM"
echo ""
echo "Estimated total with limits:"
echo "  - Reserved (minimum):  ~4.5GB"
echo "  - Limits (maximum):    ~7.5GB"
echo "  - System overhead:     ~500MB"
echo ""
echo "This configuration allows:"
echo "  ✓ Burst capability for containers when needed"
echo "  ✓ Prevents any single container from hogging memory"
echo "  ✓ Keeps ~500MB free for system/cache"
echo "  ✓ Allows swap to handle temporary spikes gracefully"
echo ""
echo -e "${YELLOW}RECOMMENDED NEXT STEPS:${NC}"
echo "1. Backup your docker-compose.yml:"
echo "   cp ~/home-server/docker-compose.yml ~/home-server/docker-compose.yml.backup"
echo ""
echo "2. Manually add the deploy sections above to your containers"
echo "   (They should go at the same indentation level as 'image', 'volumes', etc.)"
echo ""
echo "3. Recreate containers with new limits:"
echo "   cd ~/home-server && docker compose up -d"
echo ""
echo "4. Monitor container behavior:"
echo "   docker stats"
echo ""
echo -e "${BLUE}Note:${NC} These limits are based on observed usage patterns."
echo "Adjust as needed based on your specific workload."
echo ""
