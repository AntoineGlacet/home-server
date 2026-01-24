---
title: "Traefik - Reverse Proxy & TLS"
weight: 1
description: "Automatic HTTPS routing and Let's Encrypt certificate management"
---

Traefik automatically routes external HTTPS traffic to internal services and manages Let's Encrypt certificates.

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Certificate Management](#certificate-management)
- [Exposing Services](#exposing-services)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Overview

### Key Features

- **Automatic HTTPS**: All services get TLS certificates via Cloudflare DNS-01 challenge
- **Wildcard certificate**: Single cert covers `antoineglacet.com` and `*.antoineglacet.com`
- **Docker integration**: Services auto-discovered via Docker labels
- **Authentik integration**: Forward auth middleware protects sensitive services
- **Metrics export**: Prometheus scrapes Traefik metrics on port 8082

### Access Points

- **Dashboard**: https://traefik.antoineglacet.com (protected by Authentik)
- **Metrics**: http://localhost:8082/metrics (Prometheus endpoint)
- **API**: http://localhost:8080/api (if enabled)

### Architecture

```
Internet → Port 443 → Traefik → Authentik (optional) → Service
                      ↓
                   Let's Encrypt (DNS-01 challenge via Cloudflare)
```

## How It Works

### Entry Points

Traefik listens on two entry points:

1. **web** (port 80): HTTP traffic, redirects to HTTPS
2. **websecure** (port 443): HTTPS traffic with TLS

```bash
# View entry points configuration
docker compose exec traefik cat /etc/traefik/traefik.yml
```

### Routers

Routers match incoming requests and forward to services.

Defined via Docker labels:

```yaml
labels:
  - "traefik.http.routers.SERVICE_NAME.rule=Host(`service.antoineglacet.com`)"
  - "traefik.http.routers.SERVICE_NAME.entrypoints=websecure"
  - "traefik.http.routers.SERVICE_NAME.tls.certresolver=cloudflare"
```

**View active routers:**
- Dashboard → HTTP → Routers
- Or: `curl http://localhost:8080/api/http/routers | jq`

### Services

Services define backend containers and load balancing.

```yaml
labels:
  - "traefik.http.services.SERVICE_NAME.loadbalancer.server.port=3000"
  - "traefik.http.services.SERVICE_NAME.loadbalancer.server.scheme=http"
```

**View active services:**
- Dashboard → HTTP → Services

### Middlewares

Middlewares process requests before reaching services.

**Authentik forward auth:**

```yaml
labels:
  - "traefik.http.routers.SERVICE.middlewares=authentik@docker"
```

**Custom middlewares** (defined in `authentik-server` labels):
- `authentik@docker`: Forward authentication to Authentik
- `security-headers`: Add security headers
- `rate-limit`: Rate limiting

## Certificate Management

### DNS-01 Challenge

Traefik uses Cloudflare DNS-01 challenge to obtain certificates.

**Requirements:**
- Cloudflare account managing your domain
- API token with `Zone:DNS:Edit` permission
- Token in `.env` as `TRAEFIK_CLOUDFLARE_TOKEN`

**How it works:**
1. Traefik requests certificate from Let's Encrypt
2. Let's Encrypt asks for DNS TXT record
3. Traefik creates record via Cloudflare API
4. Let's Encrypt verifies record and issues certificate
5. Traefik stores certificate in `acme.json`

### Certificate Storage

Certificates stored in `config/traefik/letsencrypt/acme.json`:

```bash
# View stored certificates
docker compose exec traefik cat /letsencrypt/acme.json | jq '.cloudflare.Certificates'

# Check expiry
docker compose exec traefik cat /letsencrypt/acme.json | jq '.cloudflare.Certificates[0].domain'
```

**Important:**
- `acme.json` must have 600 permissions
- Contains private keys - keep secure
- Back up before major changes

### Certificate Dumper

`traefik-certs-dumper` extracts PEM files from `acme.json` for other services (like AdGuard).

**Output location:** `config/traefik/certs/`

```bash
# View extracted certificates
ls -la config/traefik/certs/

# Example structure:
# config/traefik/certs/
#   └── antoineglacet.com/
#       ├── certificate.crt
#       └── privatekey.key
```

### Wildcard Certificate

Configured in `docker-compose.yml`:

```yaml
command:
  - --entrypoints.websecure.http.tls.domains[0].main=antoineglacet.com
  - --entrypoints.websecure.http.tls.domains[0].sans=*.antoineglacet.com
```

This creates one certificate valid for:
- `antoineglacet.com`
- `*.antoineglacet.com` (all subdomains)

### Certificate Renewal

Traefik automatically renews certificates 30 days before expiry.

**Monitor renewals:**

```bash
# Watch Traefik logs for renewal activity
docker compose logs -f traefik | grep -i "renew\|certificate"
```

**Force renewal:**

```bash
# Delete acme.json and restart Traefik
rm config/traefik/letsencrypt/acme.json
docker compose restart traefik

# Watch logs to see new certificate request
docker compose logs -f traefik
```

## Exposing Services

### Basic Service Exposure

Add these labels to your service in `docker-compose.yml`:

```yaml
services:
  myservice:
    image: myimage:latest
    networks:
      - homelab
      - homelab_proxy
    labels:
      # Enable Traefik for this service
      - "traefik.enable=true"
      
      # Specify which network Traefik should use
      - "traefik.docker.network=homelab_proxy"
      
      # Define routing rule (hostname)
      - "traefik.http.routers.myservice.rule=Host(`myservice.${TRAEFIK_DOMAIN}`)"
      
      # Use HTTPS entry point
      - "traefik.http.routers.myservice.entrypoints=websecure"
      
      # Use Cloudflare certificate resolver
      - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
      
      # Specify container port
      - "traefik.http.services.myservice.loadbalancer.server.port=8080"
```

### Adding Authentication

Protect service with Authentik forward auth:

```yaml
labels:
  # ... basic labels above ...
  - "traefik.http.routers.myservice.middlewares=authentik@docker"
```

### Host Network Services

For services using `network_mode: host`:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myservice.rule=Host(`myservice.${TRAEFIK_DOMAIN}`)"
  - "traefik.http.routers.myservice.entrypoints=websecure"
  - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
  # Point to host.docker.internal
  - "traefik.http.services.myservice.loadbalancer.server.url=http://host.docker.internal:8080"
```

**Example:** Home Assistant, Plex

### Multiple Routers

Service can have multiple entry points:

```yaml
labels:
  # HTTP router (redirects to HTTPS)
  - "traefik.http.routers.myservice-http.rule=Host(`myservice.${TRAEFIK_DOMAIN}`)"
  - "traefik.http.routers.myservice-http.entrypoints=web"
  - "traefik.http.routers.myservice-http.middlewares=redirect-to-https"
  
  # HTTPS router
  - "traefik.http.routers.myservice.rule=Host(`myservice.${TRAEFIK_DOMAIN}`)"
  - "traefik.http.routers.myservice.entrypoints=websecure"
  - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
```

## Monitoring

### Dashboard

Access dashboard at https://traefik.antoineglacet.com

**Shows:**
- Active routers and routing rules
- Backend services and health
- Middlewares
- Certificate status
- Real-time request metrics

### Prometheus Metrics

Traefik exports metrics for Prometheus on port 8082.

**Available metrics:**
- `traefik_entrypoint_requests_total`: Total requests per entry point
- `traefik_entrypoint_request_duration_seconds`: Request duration histogram
- `traefik_service_requests_total`: Requests per backend service
- `traefik_service_request_duration_seconds`: Backend response time

**Query examples:**

```promql
# Request rate per service
rate(traefik_service_requests_total[5m])

# Average response time
avg(traefik_service_request_duration_seconds_sum / traefik_service_request_duration_seconds_count)

# Error rate
sum(rate(traefik_service_requests_total{code=~"5.."}[5m]))
```

### Logs

```bash
# Follow all Traefik logs
docker compose logs -f traefik

# Filter for errors
docker compose logs -f traefik | grep -i error

# Filter for specific service
docker compose logs -f traefik | grep myservice

# Check access logs
docker compose logs traefik | grep "HTTP/1.1\" 200"
```

### Health Check

```bash
# Ping Traefik
curl http://localhost:8080/ping

# Should return: OK
```

## Troubleshooting

### Certificate Issues

#### Certificate not issued

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

# 5. Force new certificate
rm config/traefik/letsencrypt/acme.json
docker compose restart traefik
```

#### Certificate expired

```bash
# Should auto-renew 30 days before expiry
# If not, check logs:
docker compose logs traefik | grep -i renew

# Force renewal:
rm config/traefik/letsencrypt/acme.json
docker compose restart traefik
```

### Routing Issues

#### Service not accessible

```bash
# 1. Check service is running
docker compose ps myservice

# 2. Verify Traefik labels
docker inspect myservice | jq '.[0].Config.Labels'

# 3. Check if router exists in Traefik
# Dashboard → HTTP → Routers → look for myservice

# 4. Verify service is on homelab_proxy network
docker inspect myservice | jq '.[0].NetworkSettings.Networks'

# 5. Test from inside Traefik container
docker compose exec traefik wget -O- http://myservice:8080
```

#### 404 Not Found

```bash
# Router not matching request
# 1. Check Host rule matches exactly
# 2. Verify DNS points to server
nslookup myservice.antoineglacet.com

# 3. Check Traefik dashboard for router
```

#### 502 Bad Gateway

```bash
# Backend service unreachable
# 1. Check service is running
docker compose ps myservice

# 2. Verify port in labels matches container
docker compose exec traefik wget -O- http://myservice:XXXX

# 3. Check service logs
docker compose logs myservice
```

#### 503 Service Unavailable

```bash
# No backend available
# 1. Service not on correct network
docker inspect myservice | jq '.[0].NetworkSettings.Networks'

# 2. Service not started
docker compose ps myservice

# 3. Health check failing
docker inspect myservice | jq '.[0].State.Health'
```

### Authentik Middleware Issues

#### Authentication loop

```bash
# 1. Clear browser cookies for *.antoineglacet.com

# 2. Check Authentik is running
docker compose ps | grep authentik

# 3. Verify middleware configuration
docker inspect authentik-server | jq '.[0].Config.Labels' | grep middleware

# 4. Check Authentik logs
docker compose logs authentik-server | tail -50
```

### Performance Issues

#### Slow response times

```bash
# 1. Check Traefik metrics
curl http://localhost:8082/metrics | grep duration

# 2. Check if backend is slow
docker compose exec traefik time wget -O- http://myservice:8080

# 3. Enable access logs for debugging
# Add to docker-compose.yml command:
# - --accesslog=true
```

#### High CPU/memory usage

```bash
# 1. Check Traefik resource usage
docker stats traefik

# 2. Review number of active connections
# Dashboard → Overview

# 3. Consider adding rate limiting
# - "traefik.http.middlewares.rate-limit.ratelimit.average=100"
```

### Checking Configuration

```bash
# View full Traefik configuration
docker compose exec traefik cat /etc/traefik/traefik.yml

# View dynamic configuration (from Docker labels)
curl http://localhost:8080/api/http/routers | jq
curl http://localhost:8080/api/http/services | jq
curl http://localhost:8080/api/http/middlewares | jq

# Validate configuration
docker compose config traefik
```

### Common Mistakes

1. **Service not on homelab_proxy network**
   - Solution: Add to both `homelab` and `homelab_proxy` networks

2. **Wrong port in labels**
   - Solution: Use container's internal port, not published port

3. **Missing traefik.docker.network label**
   - Solution: Add `traefik.docker.network=homelab_proxy`

4. **DNS not pointing to server**
   - Solution: Verify A record in Cloudflare

5. **Firewall blocking port 443**
   - Solution: Check `ufw` or `iptables`

### Debugging Workflow

```bash
# 1. Verify service is running
docker compose ps myservice

# 2. Check service logs
docker compose logs myservice

# 3. Check Traefik can reach service
docker compose exec traefik wget -O- http://myservice:PORT

# 4. Verify DNS resolves
nslookup myservice.antoineglacet.com

# 5. Check Traefik logs
docker compose logs traefik | grep myservice

# 6. Verify certificate exists
docker compose exec traefik cat /letsencrypt/acme.json | jq '.cloudflare.Certificates'

# 7. Test from outside
curl -v https://myservice.antoineglacet.com
```
