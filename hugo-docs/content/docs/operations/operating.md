---
title: "Operating Guide"
weight: 1
description: "Complete guide to day-to-day operations of the home server"
---

Complete guide to day-to-day operations of the home server.

## Table of Contents

- [Basic Operations](#basic-operations)
- [Helper Scripts](#helper-scripts)
- [Environment & Secrets](#environment--secrets)
- [Networking](#networking)
- [Storage & Backups](#storage--backups)
- [Useful Commands](#useful-commands)

## Basic Operations

### Starting & Stopping Services

```bash
# Start everything
docker compose up -d

# Stop everything (preserves volumes/data)
docker compose down

# Restart specific service
docker compose restart [service-name]

# Stop specific service
docker compose stop [service-name]

# Start specific service
docker compose start [service-name]

# Recreate service (useful after config changes)
docker compose up -d --force-recreate [service-name]
```

### Viewing Logs

```bash
# Follow logs for all services
docker compose logs -f

# Follow logs for specific service
docker compose logs -f [service-name]

# View last 100 lines
docker compose logs --tail=100 [service-name]

# View logs since timestamp
docker compose logs --since 2026-01-24T10:00:00 [service-name]
```

### Updating Services

```bash
# Pull latest images
docker compose pull

# Apply updates (recreate containers with new images)
docker compose up -d

# Update specific service
docker compose pull [service-name]
docker compose up -d [service-name]

# View what will be updated
docker compose pull && docker compose up -d --dry-run
```

### Checking Status

```bash
# View all containers
docker compose ps

# View detailed status
docker compose ps -a

# Check resource usage
docker stats

# Quick health overview
./scripts/health-check.sh
```

### Cleanup

```bash
# Remove stopped containers
docker compose rm

# Clean up unused Docker resources
docker system prune

# Aggressive cleanup (includes unused images and volumes)
docker system prune -a --volumes  # ⚠️ WARNING: removes unused volumes!

# View disk usage
docker system df
```

## Helper Scripts

Located in `scripts/` directory:

### health-check.sh

Quick overview of system health, disk space, memory, and container status.

```bash
./scripts/health-check.sh
```

**Shows:**
- Disk space (root and `/media/data`)
- Memory and swap usage with color-coded warnings
- Container status (running, stopped, unhealthy)
- Recent container restarts

### optimize-performance.sh

Apply kernel tuning for better performance under load. Addresses SSH lag and memory pressure.

```bash
sudo ./scripts/optimize-performance.sh
```

**Changes:**
- Increases swappiness to 60 (proactive memory management)
- Optimizes network buffers (20x larger for gigabit LAN)
- Enables hardware offload (reduces CPU for network I/O)
- Tunes kernel parameters for server workload
- Creates automatic backups and rollback script

See `QUICK_START.md` and `PERFORMANCE_OPTIMIZATION.md` for details.

### backup-postgres.sh

Backup PostgreSQL databases (Authentik).

```bash
./scripts/backup-postgres.sh
```

**Creates:**
- Timestamped SQL dumps in `backups/postgres/`
- Separate dump for Authentik database

### validate-backups.sh

Verify backup integrity.

```bash
./scripts/validate-backups.sh
```

### add-docker-memory-limits.sh

Analyze memory usage and recommend Docker memory limits.

```bash
./scripts/add-docker-memory-limits.sh
```

**Output:**
- Memory usage analysis per container
- Recommended `deploy.resources.limits.memory` values
- Instructions for adding limits to `docker-compose.yml`

## Environment & Secrets

### .env File

All secrets and configuration live in `.env` next to `docker-compose.yml`.

**Critical variables:**

```bash
# User/System
PUID=1000                          # User ID for file permissions
PGID=1000                          # Group ID for file permissions
TZ=Asia/Tokyo                      # Timezone

# Networking
LOCAL_NETWORK=10.13.0.0/16         # Local network CIDR
TRAEFIK_DOMAIN=antoineglacet.com   # Base domain for all services

# Traefik / TLS
TRAEFIK_ACME_EMAIL=admin@example.com
TRAEFIK_CLOUDFLARE_TOKEN=xxx       # Cloudflare API token for DNS-01 challenge

# Authentik
AUTHENTIK_SECRET_KEY=xxx           # Secret key for Authentik (generate random)
AUTHENTIK_POSTGRESQL__PASSWORD=xxx # Database password
AUTHENTIK_REDIS__PASSWORD=xxx      # Redis password

# VPN
NORDVPN_PRIVATE_KEY=xxx            # NordVPN private key

# Storage Paths
DATA=/media/data
BACKUP=/media/data/backup
DOWNLOADS=/media/data/downloads
MEDIA=/media/data/media
MOVIES=/media/data/media/movies
TV=/media/data/media/tv
HOMESERVER=/home/antoine/home-server

# MQTT
MQTT_SERVER=mqtt://mqtt:1883
MQTT_USER=xxx
MQTT_PASSWORD=xxx
ZIGBEE_ADAPTOR_PATH=/dev/serial/by-id/usb-xxx

# Grafana OAuth
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=xxx      # From Authentik
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=xxx  # From Authentik

# Alerting
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx
```

**Setup:**

```bash
# Copy template
cp .env.example .env

# Edit with your values
nano .env

# Verify required variables
grep -E "(TRAEFIK_DOMAIN|AUTHENTIK_SECRET_KEY|NORDVPN_PRIVATE_KEY)" .env
```

**Security:**
- Never commit `.env` to version control
- Keep encrypted backups in secure location
- Rotate secrets periodically
- Use strong, random values for all secrets

### Per-Service Configuration

Service-specific configuration lives in `config/` directory and is bind-mounted into containers.

```
config/
├── authentik/        # Authentik media and config
├── grafana/          # Dashboards, datasources, alerting
├── homeassistant/    # Home Assistant automations
├── prometheus/       # Scrape configs and alerts
├── traefik/          # TLS certificates
└── ...
```

**Important:**
- Always run `docker compose` from repo root so relative paths work
- Back up `config/` before major changes
- Some services regenerate config on first run

## Networking

### Network Overview

Three Docker networks isolate traffic:

#### homelab (internal bridge)

Default network for service-to-service communication.

```bash
# View network details
docker network inspect homelab

# Containers can reach each other by name:
# - prometheus → http://node_exporter:9100
# - grafana → http://loki:3100
```

#### homelab_proxy (external bridge)

Carries HTTP/HTTPS traffic through Traefik.

```bash
# Create if missing
docker network create homelab_proxy

# Services exposed via web UI join this network
docker network inspect homelab_proxy
```

**Services on this network:**
- Traefik (reverse proxy)
- Authentik (SSO)
- Grafana, Homepage, Glances (dashboards)
- All *arr services
- Any service with `traefik.enable=true` label

#### Host network

Special cases requiring host network access:

- **home-assistant**: Needs network discovery for IoT devices
- **plex**: Requires DLNA discovery and hardware acceleration
- **node_exporter**: Monitors host system metrics

```bash
# These containers appear on host network
# Access via host IP or localhost
```

### VPN Routing

Transmission and Prowlarr share nordlynx container's network namespace:

```yaml
network_mode: service:nordlynx
```

This ensures all their traffic routes through VPN tunnel.

**Verify VPN:**

```bash
# Check connection
docker compose logs nordlynx | grep -i connected

# Verify IP is VPN server
docker compose exec transmission curl ifconfig.me
```

### DNS & DHCP

AdGuard Home provides:
- Network-wide ad blocking
- DNS server for local network
- DHCP server (optional)

**Access:** https://adguard.antoineglacet.com

**Dynamic DNS:** `ddclient` keeps Cloudflare DNS updated with current public IP.

## Storage & Backups

### Media Libraries

Media files mount from host paths defined in `.env`:

```bash
MEDIA=/media/data/media
MOVIES=/media/data/media/movies
TV=/media/data/media/tv
DOWNLOADS=/media/data/downloads
LIBRARY=/media/data/media/calibre-library
```

**Permissions:**
- Files owned by `${PUID}:${PGID}` (usually 1000:1000)
- Containers run as this user for file access

### Duplicati Backups

Encrypted backups of `${BACKUP}` directory.

**Access:** https://duplicati.antoineglacet.com

**Configure:**
1. Add backup job in UI
2. Select source: `/backups` (mounted from `${BACKUP}`)
3. Choose destination (S3, B2, local, etc.)
4. Set schedule and retention policy
5. Encrypt with strong passphrase

### PostgreSQL Backups

Authentik database backups:

```bash
# Manual backup
./scripts/backup-postgres.sh

# Output: backups/postgres/authentik_YYYY-MM-DD_HH-MM-SS.sql
```

**Restore:**

```bash
# Stop Authentik
docker compose stop authentik-server authentik-worker

# Restore database
docker compose exec -T postgres psql -U authentik -d authentik < backups/postgres/authentik_2026-01-24_10-00-00.sql

# Restart Authentik
docker compose start authentik-server authentik-worker
```

### Samba File Sharing

Exposes `${DATA}` to Windows clients.

**Access:** `\\<server-ip>\data`

**Credentials:** `${SAMBA_USER}` / `${SAMBA_PASSWORD}` from `.env`

## Useful Commands

### Container Management

```bash
# Execute command in container
docker compose exec [service] [command]

# Open shell in container
docker compose exec [service] /bin/bash
docker compose exec [service] /bin/sh

# Copy files to/from container
docker compose cp [service]:/path/in/container /local/path
docker compose cp /local/path [service]:/path/in/container

# View container details
docker inspect [container-name]

# View container resource limits
docker inspect [container-name] | jq '.[0].HostConfig.Memory'
```

### Networking

```bash
# Test connectivity from container
docker compose exec [service] ping -c 3 google.com
docker compose exec [service] curl -I https://google.com

# Check which network container is on
docker inspect [container-name] | jq '.[0].NetworkSettings.Networks'

# List all networks
docker network ls

# View network details
docker network inspect homelab
```

### Logs & Debugging

```bash
# Follow Docker daemon logs
journalctl -u docker -f

# Check container healthcheck
docker inspect [container-name] | jq '.[0].State.Health'

# View container startup command
docker inspect [container-name] | jq '.[0].Config.Cmd'

# Check container environment variables
docker compose exec [service] env
```

### Backup & Restore

```bash
# Backup entire config directory
tar -czf ~/backup-$(date +%F).tar.gz /home/antoine/home-server/config

# Backup with docker volumes
docker run --rm -v home-server_postgres_data:/data -v ~/backups:/backup alpine tar czf /backup/postgres-data-$(date +%F).tar.gz -C /data .

# Restore config
tar -xzf ~/backup-2026-01-24.tar.gz -C /

# List volumes
docker volume ls

# Inspect volume
docker volume inspect home-server_postgres_data
```

### Performance

```bash
# View resource usage
docker stats

# View top processes in container
docker compose top [service]

# Check host resources
free -h
df -h
vmstat 1 5

# Network bandwidth
iftop  # or nethogs
```
