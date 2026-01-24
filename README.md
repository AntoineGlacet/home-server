# 🛰️ Home Server on Docker

> Infrastructure-as-code for my Dell OptiPlex 3050 home lab. Every service runs in Docker, networks are segmented, and a single `.env` file keeps secrets out of version control.

## Hardware

**Dell OptiPlex 3050**
- CPU: Intel Core i5-7500T (4 cores @ 2.70GHz)
- RAM: 8GB DDR4
- Storage: 98GB system drive + 5.5TB data drive
- OS: Ubuntu 24.04.3 LTS

## Quick Start

```bash
# Clone and setup
git clone <repo-url> ~/home-server
cd ~/home-server

# Create .env from template
cp .env.example .env
nano .env  # Configure your secrets and paths

# Create required network
docker network create homelab_proxy

# Start everything
docker compose up -d

# Check status
docker compose ps
./scripts/health-check.sh
```

## Stack Overview

All services live in one `docker-compose.yml`:

| Category | Services |
| --- | --- |
| **Smart Home** | Home Assistant, Mosquitto MQTT, Zigbee2MQTT |
| **Media** | Plex, Sonarr, Radarr, Bazarr, Transmission, Prowlarr, Calibre Web |
| **Monitoring** | Prometheus, Grafana, Loki, Promtail, cAdvisor, Glances, Node Exporter |
| **Infrastructure** | Traefik, Authentik, AdGuard Home, PostgreSQL, Redis |
| **Utilities** | Homepage, Duplicati, Syncthing, Samba, DDClient, FlareSolverr |

## Common Operations

```bash
# Start/stop services
docker compose up -d              # Start everything
docker compose down               # Stop everything
docker compose restart [service]  # Restart specific service

# View logs
docker compose logs -f [service]  # Follow logs

# Update services
docker compose pull               # Pull latest images
docker compose up -d              # Recreate with new images

# System health
./scripts/health-check.sh         # Quick health overview
docker compose ps                 # Container status
```

## Key Services

| Service | URL | Purpose |
| --- | --- | --- |
| **Homepage** | https://homepage.antoineglacet.com | Dashboard with links to all services |
| **Traefik** | https://traefik.antoineglacet.com | Reverse proxy & TLS management |
| **Authentik** | https://authentik.antoineglacet.com | Single Sign-On & authentication |
| **Grafana** | https://grafana.antoineglacet.com | Metrics dashboards & alerting |
| **Glances** | https://glances.antoineglacet.com | Real-time system monitoring |
| **AdGuard** | https://adguard.antoineglacet.com | DNS & ad blocking |
| **Home Assistant** | https://homeassistant.antoineglacet.com | Home automation |
| **Plex** | https://plex.antoineglacet.com | Media server |

## Architecture

### Networks

Three network tiers isolate traffic:

- **`homelab`**: Internal service-to-service communication
- **`homelab_proxy`**: External HTTPS traffic via Traefik
- **Host network**: Special cases (Home Assistant, Plex, Node Exporter)

### Key Components

- **Traefik**: Reverse proxy with automatic Let's Encrypt certificates
- **Authentik**: SSO and forward authentication for web services
- **Prometheus + Grafana**: Metrics collection and visualization
- **Loki + Promtail**: Centralized log aggregation
- **AdGuard Home**: Network-wide DNS and ad blocking
- **NordLynx VPN**: Protects Transmission and Prowlarr traffic

## Documentation

### Core Guides

- **[Operating Guide](docs/operating.md)** - Day-to-day operations, helper scripts, environment setup
- **[Traefik](docs/traefik.md)** - Reverse proxy configuration, TLS certificates, routing
- **[Authentik](docs/authentik.md)** - SSO setup, user management, OAuth integration
- **[Monitoring](docs/monitoring.md)** - Prometheus, Grafana, Loki, alerting, dashboards
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

### Performance & Optimization

- **[Quick Start](docs/QUICK_START.md)** - Quick performance fix guide (SSH lag)
- **[Performance Optimization](docs/PERFORMANCE_OPTIMIZATION.md)** - Detailed kernel tuning and optimization

### Deployment

- **[Deployment Checklist](docs/deployment/DEPLOYMENT_CHECKLIST.md)** - Pre-deployment verification
- **[Deployment Notes](docs/deployment/DEPLOYMENT_NOTES.md)** - Deployment history and notes
- **[Alerting Migration](docs/deployment/ALERTING_MIGRATION.md)** - Alertmanager to Grafana migration

### Planning & Status

- **[Implementation Status](docs/planning/IMPLEMENTATION_STATUS.md)** - Current state of all services
- **[Next Steps](docs/planning/NEXT_STEPS.md)** - Planned improvements and roadmap
- **[Security Remediation](docs/planning/SECURITY_REMEDIATION.md)** - Security hardening notes

### Additional Resources

- **[Grafana Setup](docs/grafana-setup.md)** - Grafana configuration details
- **[Performance Tuning](docs/performance-tuning.md)** - System performance tuning
- **[Post-Commit Steps](docs/post-commit-steps.md)** - Steps after committing changes
