---
title: "Troubleshooting Guide"
weight: 1
description: "Common issues and solutions for all home server components"
---

Common issues and solutions for the home server.

## Table of Contents

- [General Issues](#general-issues)
- [Networking](#networking)
- [Traefik & HTTPS](#traefik--https)
- [Authentik](#authentik)
- [Monitoring](#monitoring)
- [Performance](#performance)
- [VPN](#vpn)
- [Storage](#storage)
- [Container Issues](#container-issues)

## General Issues

### Services Won't Start

```bash
# Check for port conflicts
docker compose ps
sudo netstat -tulpn | grep -E ':(80|443|9090|3000)'

# Check logs for specific service
docker compose logs [service-name]

# Verify .env file exists and is readable
ls -la .env
cat .env | grep TRAEFIK_DOMAIN

# Ensure networks exist
docker network ls | grep homelab
docker network create homelab_proxy  # if missing

# Check Docker daemon
systemctl status docker

# View Docker daemon logs
journalctl -u docker -f
```

### Can't Connect to Server

```bash
# Check server is online
ping <server-ip>

# Check SSH is responding
telnet <server-ip> 22

# Verify services are running
docker compose ps

# Check firewall rules
sudo ufw status
sudo iptables -L
```

### High CPU/Memory Usage

```bash
# Quick health check
./scripts/health-check.sh

# Identify resource hogs
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | sort -k2 -hr

# Check host resources
htop
free -h
vmstat 1 5

# Apply performance optimizations
sudo ./scripts/optimize-performance.sh
```

## Networking

### DNS Resolution Issues

```bash
# Test DNS resolution
nslookup service.antoineglacet.com

# Check if pointing to correct IP
dig service.antoineglacet.com +short

# Verify Cloudflare DNS records
# Visit: https://dash.cloudflare.com

# Check DDClient is updating
docker compose logs ddclient

# Test local DNS (AdGuard)
nslookup google.com 10.13.1.1
```

### Can't Access Service Locally

```bash
# Check service is running
docker compose ps [service]

# Verify port is exposed
docker inspect [service] | jq '.[0].NetworkSettings.Ports'

# Test from host
curl http://localhost:PORT

# Check if on correct network
docker inspect [service] | jq '.[0].NetworkSettings.Networks'

# Test connectivity between containers
docker compose exec [service1] ping [service2]
docker compose exec [service1] curl http://[service2]:PORT
```

### Network Isolation Issues

```bash
# Verify network exists
docker network ls | grep homelab

# Inspect network
docker network inspect homelab
docker network inspect homelab_proxy

# Check which containers are connected
docker network inspect homelab | jq '.[0].Containers'

# Reconnect container to network
docker network connect homelab_proxy [container]
```

## Traefik & HTTPS

### Certificate Not Issued

```bash
# 1. Check Traefik logs
docker compose logs traefik | grep -i "certificate\|acme\|error"

# 2. Verify Cloudflare token
docker compose exec traefik env | grep CLOUDFLARE

# 3. Test Cloudflare API access
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $TRAEFIK_CLOUDFLARE_TOKEN" \
  -H "Content-Type: application/json"

# 4. Check acme.json permissions
ls -la config/traefik/letsencrypt/acme.json
# Should be: -rw------- (600)

# 5. Check acme.json content
docker compose exec traefik cat /letsencrypt/acme.json | jq

# 6. Force new certificate
rm config/traefik/letsencrypt/acme.json
docker compose restart traefik
docker compose logs -f traefik
```

### 404 Not Found

```bash
# Router not matching request

# 1. Check Host rule matches exactly
docker inspect [service] | jq '.[0].Config.Labels' | grep rule

# 2. Verify DNS points to server
nslookup service.antoineglacet.com

# 3. Check Traefik dashboard for router
# Visit: https://traefik.antoineglacet.com

# 4. View active routers
curl http://localhost:8080/api/http/routers | jq '.[] | {name: .name, rule: .rule}'
```

### 502 Bad Gateway

```bash
# Backend service unreachable

# 1. Check service is running
docker compose ps [service]

# 2. Verify port in labels matches container port
docker inspect [service] | jq '.[0].Config.ExposedPorts'

# 3. Test connectivity from Traefik
docker compose exec traefik wget -O- http://[service]:PORT

# 4. Check service logs
docker compose logs [service]

# 5. Verify service is on homelab_proxy network
docker inspect [service] | jq '.[0].NetworkSettings.Networks' | grep homelab_proxy
```

### 503 Service Unavailable

```bash
# No backend available

# 1. Service not started
docker compose ps [service]

# 2. Service not on correct network
docker inspect [service] | jq '.[0].NetworkSettings.Networks'

# 3. Health check failing
docker inspect [service] | jq '.[0].State.Health'

# 4. Check Traefik sees service
curl http://localhost:8080/api/http/services | jq
```

### SSL Certificate Expired

```bash
# Should auto-renew 30 days before expiry

# Check certificate expiry
echo | openssl s_client -servername service.antoineglacet.com -connect service.antoineglacet.com:443 2>/dev/null | openssl x509 -noout -dates

# Check Traefik logs for renewal attempts
docker compose logs traefik | grep -i renew

# Force renewal
rm config/traefik/letsencrypt/acme.json
docker compose restart traefik
```

## Authentik

### Can't Login

```bash
# 1. Verify user exists and is active
docker compose exec postgres psql -U authentik -d authentik -c "SELECT username, is_active FROM authentik_core_user;"

# 2. Check Authentik logs
docker compose logs authentik-server | grep -i "login\|authentication"

# 3. Test PostgreSQL connection
docker compose exec postgres pg_isready -U authentik -d authentik

# 4. Reset admin password
docker compose exec authentik-server ak create_admin_group

# 5. Create recovery key
docker compose exec authentik-server ak create_recovery_key 10 akadmin
```

### Redirect Loop

```bash
# 1. Clear browser cookies for *.antoineglacet.com

# 2. Check service ROOT_URL matches Traefik route
# For Grafana:
docker compose exec grafana env | grep ROOT_URL
# Should be: https://grafana.antoineglacet.com

# 3. Verify OAuth redirect URI in Authentik
# Applications → Providers → [provider] → Redirect URIs

# 4. Check forward auth middleware
docker inspect authentik-server | jq '.[0].Config.Labels' | grep forwardauth

# 5. Test forward auth endpoint
curl -I http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
```

### 502 Error on Authentik

```bash
# 1. Check Authentik containers running
docker compose ps | grep authentik

# 2. Verify PostgreSQL is healthy
docker compose exec postgres pg_isready -U authentik -d authentik

# 3. Check Authentik health
curl -I https://authentik.antoineglacet.com/-/health/live/

# 4. Check logs
docker compose logs authentik-server --tail=50
docker compose logs authentik-worker --tail=50

# 5. Restart Authentik stack
docker compose restart authentik-server authentik-worker authentik-redis
```

### OAuth Login Fails

```bash
# 1. Verify client ID/secret match
# Check .env vs Authentik provider settings

# 2. Check redirect URI matches exactly
# In Authentik: Applications → Providers → [provider]
# Should match application's expected callback URL

# 3. Test token endpoint
curl -X POST https://authentik.antoineglacet.com/application/o/token/ \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET"

# 4. Check Authentik events
# System → Events → Logs
```

## Monitoring

### Prometheus Not Scraping Targets

```bash
# Check target status
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# View unhealthy targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up")'

# Common issues:

# - node_exporter on host network
docker compose ps node_exporter
curl http://172.17.0.1:9100/metrics

# - Service not on homelab network
docker inspect [service] | jq '.[0].NetworkSettings.Networks'

# - Firewall blocking
sudo ufw status
sudo iptables -L

# Restart Prometheus
docker compose restart prometheus
docker compose logs prometheus
```

### Grafana Can't Query Data

```bash
# 1. Check datasources configured
docker compose exec grafana cat /etc/grafana/provisioning/datasources/datasources.yml

# 2. Verify Prometheus reachable from Grafana
docker compose exec grafana curl http://prometheus:9090/-/ready

# 3. Verify Loki reachable
docker compose exec grafana curl http://loki:3100/ready

# 4. Check Grafana logs
docker compose logs grafana | grep -i "datasource\|error"

# 5. Test datasource in UI
# Grafana → Configuration → Data sources → [datasource] → Test
```

### No Logs in Loki

```bash
# 1. Check Promtail is running
docker compose ps promtail

# 2. Verify Promtail can reach Loki
docker compose exec promtail wget -O- http://loki:3100/ready

# 3. Check Promtail logs
docker compose logs promtail

# 4. Verify Docker socket mounted
docker inspect promtail | jq '.[0].Mounts[] | select(.Source == "/var/run/docker.sock")'

# 5. Query Loki API
curl http://loki:3100/loki/api/v1/labels

# 6. Check Loki logs
docker compose logs loki
```

### Alerts Not Firing

```bash
# 1. Check alert rules loaded
# Grafana → Alerting → Alert rules

# 2. Verify Discord webhook configured
env | grep DISCORD_WEBHOOK_URL

# 3. Test webhook
curl -H "Content-Type: application/json" \
  -d '{"content":"Test alert"}' \
  $DISCORD_WEBHOOK_URL

# 4. Check Grafana logs
docker compose logs grafana | grep -i alert

# 5. Verify contact points
# Grafana → Alerting → Contact points → Test

# 6. Check notification policies
# Grafana → Alerting → Notification policies
```

## Performance

### SSH Lag / Slow Response

```bash
# 1. Quick health check
./scripts/health-check.sh

# 2. Check memory pressure
free -h
vmstat 1 5

# 3. Identify resource hogs
docker stats --no-stream | sort -k4 -hr

# 4. Apply kernel optimizations
sudo ./scripts/optimize-performance.sh

# 5. Add Docker memory limits
./scripts/add-docker-memory-limits.sh

# 6. Check swap usage
free -h | grep Swap
swapon --show
```

### Container Using Too Much Memory

```bash
# 1. Identify culprit
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | sort -k2 -hr

# 2. Check container logs for memory errors
docker compose logs [service] | grep -i "memory\|oom"

# 3. Add memory limit
# In docker-compose.yml:
deploy:
  resources:
    limits:
      memory: 512M

# 4. Restart with limit
docker compose up -d [service]

# 5. Monitor
docker stats [service]
```

### High Disk I/O

```bash
# 1. Check disk I/O
iostat -x 1 5

# 2. Find process causing I/O
iotop -o

# 3. Check Loki/Prometheus disk usage
du -sh data/loki data/prometheus

# 4. Clean up old data
# Adjust retention in configs

# 5. Check for log flooding
docker compose logs [service] --tail=100

# 6. Optimize database
# For PostgreSQL:
docker compose exec postgres vacuumdb -U authentik -d authentik --analyze
```

## VPN

### VPN Not Connecting

```bash
# 1. Check nordlynx container
docker compose ps nordlynx
docker compose logs nordlynx

# 2. Verify private key set
env | grep NORDVPN_PRIVATE_KEY

# 3. Check connection status
docker compose exec transmission ping -c 3 google.com

# 4. Verify IP is VPN server
docker compose exec transmission curl ifconfig.me

# 5. Restart VPN
docker compose restart nordlynx
sleep 10
docker compose restart transmission prowlarr
```

### Transmission Can't Download

```bash
# 1. Verify VPN is working
docker compose exec transmission curl ifconfig.me
# Should NOT be your home IP

# 2. Check Transmission is reachable
curl http://localhost:9091

# 3. Verify downloads directory permissions
ls -la ${DOWNLOADS}
# Should be owned by ${PUID}:${PGID}

# 4. Check Transmission logs
docker compose logs transmission

# 5. Test connectivity
docker compose exec transmission ping -c 3 google.com
```

### Can't Access Prowlarr/Transmission UI

```bash
# 1. Verify nordlynx publishes ports
docker inspect nordlynx | jq '.[0].NetworkSettings.Ports'

# 2. Check Traefik routes to nordlynx
# Dashboard → Services → transmission, prowlarr

# 3. Test direct access
curl http://localhost:9091  # Transmission
curl http://localhost:9696  # Prowlarr

# 4. Check nordlynx logs
docker compose logs nordlynx
```

## Storage

### Disk Space Full

```bash
# 1. Check disk usage
df -h

# 2. Find large files
du -sh /media/data/* | sort -h
du -sh /home/antoine/home-server/data/* | sort -h

# 3. Clean Docker resources
docker system prune -a --volumes  # ⚠️ Removes unused volumes!
docker system df

# 4. Clean old logs
docker compose logs [service] --since 24h > /dev/null 2>&1
journalctl --vacuum-time=7d

# 5. Clean Loki data
rm -rf data/loki/chunks/*

# 6. Clean Prometheus data (old metrics)
# Adjust retention in prometheus.yml
```

### Permission Denied Errors

```bash
# 1. Check file ownership
ls -la config/[service]/

# 2. Verify PUID/PGID in .env
grep -E "PUID|PGID" .env

# 3. Fix ownership
sudo chown -R ${PUID}:${PGID} config/[service]/
sudo chown -R ${PUID}:${PGID} data/[service]/

# 4. Check directory permissions
chmod 755 config/[service]/

# 5. For sensitive files (like acme.json)
chmod 600 config/traefik/letsencrypt/acme.json
```

### Backup Failed

```bash
# 1. Check backup script logs
cat logs/backup-*.log

# 2. Verify backup destination exists
ls -la ${BACKUP}

# 3. Check disk space at destination
df -h ${BACKUP}

# 4. Test backup manually
./scripts/backup-postgres.sh

# 5. Check Duplicati logs
docker compose logs duplicati
```

## Container Issues

### Container Keeps Restarting

```bash
# 1. Check restart count
docker compose ps -a

# 2. View recent logs
docker compose logs --tail=100 [service]

# 3. Check exit code
docker inspect [service] | jq '.[0].State.ExitCode'

# 4. Check healthcheck
docker inspect [service] | jq '.[0].State.Health'

# 5. Disable autoheal temporarily
docker compose stop autoheal

# 6. Check resource limits
docker inspect [service] | jq '.[0].HostConfig | {Memory, MemorySwap, CpuShares}'
```

### Container Won't Start

```bash
# 1. Check logs for error
docker compose logs [service]

# 2. Verify dependencies
# Check depends_on in docker-compose.yml

# 3. Check for conflicting containers
docker ps -a | grep [service]

# 4. Remove and recreate
docker compose rm -f [service]
docker compose up -d [service]

# 5. Check configuration
docker compose config [service]
```

### Healthcheck Failing

```bash
# 1. Check healthcheck command
docker inspect [service] | jq '.[0].Config.Healthcheck'

# 2. Run healthcheck manually
docker compose exec [service] [healthcheck-command]

# Example for postgres:
docker compose exec postgres pg_isready -U postgres

# 3. Check service is actually responding
docker compose exec [service] curl http://localhost:PORT

# 4. Adjust healthcheck timing
# In docker-compose.yml:
healthcheck:
  interval: 30s
  timeout: 10s
  start_period: 60s  # Increase if slow to start
```

## Zigbee/Home Automation

### Zigbee2MQTT Can't Find USB Adapter

```bash
# 1. List USB devices
ls -la /dev/serial/by-id/

# 2. Verify path in .env
grep ZIGBEE_ADAPTOR_PATH .env

# 3. Check device exists
ls -la /dev/ttyUSB0

# 4. Check permissions
sudo chmod 666 /dev/ttyUSB0

# 5. Add user to dialout group
sudo usermod -aG dialout antoine

# 6. Restart container
docker compose restart zigbee2mqtt
```

### Home Assistant Discovery Not Working

```bash
# 1. Verify Home Assistant on host network
docker inspect home-assistant | jq '.[0].HostConfig.NetworkMode'
# Should be: "host"

# 2. Check if broadcast/multicast working
# Some integrations need this

# 3. Check firewall rules
sudo ufw status

# 4. Verify mDNS/Avahi
systemctl status avahi-daemon

# 5. Check Home Assistant logs
docker compose logs home-assistant | grep -i discovery
```

## Getting Help

### Information to Gather

When reporting issues:

```bash
# 1. System info
uname -a
docker --version
docker compose version

# 2. Container status
docker compose ps

# 3. Service logs
docker compose logs [service] --tail=100

# 4. Resource usage
docker stats --no-stream

# 5. Network info
docker network ls
docker network inspect homelab

# 6. Recent changes
git log -5 --oneline
```

### Debug Mode

Enable verbose logging:

```bash
# Traefik
# Add to command in docker-compose.yml:
- --log.level=DEBUG

# Authentik
environment:
  - AUTHENTIK_LOG_LEVEL=debug

# Restart and view logs
docker compose restart [service]
docker compose logs -f [service]
```

### Useful Resources

- `IMPLEMENTATION_STATUS.md` - Current state of all services
- `SECURITY_REMEDIATION.md` - Security notes
- `PERFORMANCE_OPTIMIZATION.md` - Performance tuning
- `ALERTING_MIGRATION.md` - Alerting setup
- GitHub Issues - Known problems and solutions
