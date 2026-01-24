---
title: "Authentik - SSO & Authentication"
weight: 2
description: "Single Sign-On and forward authentication for all web services"
---

Authentik provides Single Sign-On (SSO) and forward authentication for all web services.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [How Forward Auth Works](#how-forward-auth-works)
- [Protected Services](#protected-services)
- [User Management](#user-management)
- [Grafana OAuth Integration](#grafana-oauth-integration)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Overview

### What is Authentik?

Authentik is an identity provider (IdP) that handles:
- User authentication (login)
- Single Sign-On across services
- OAuth2/OIDC provider
- Forward authentication for Traefik
- User and group management
- Multi-factor authentication (MFA)

### Access Points

- **Admin Interface**: https://authentik.antoineglacet.com
- **User Portal**: https://authentik.antoineglacet.com/if/user/
- **API**: https://authentik.antoineglacet.com/api/v3/

### Key Features

- **Forward Auth**: Protects services via Traefik middleware
- **OAuth2/OIDC**: Integrates with apps like Grafana
- **User Management**: Create users, groups, and permissions
- **Flows**: Customizable authentication/authorization workflows
- **Providers**: Configure per-application access

## Architecture

### Components

```
authentik-server  → Web UI, OAuth provider, forward auth endpoint
authentik-worker  → Background tasks (email, scheduled jobs)
authentik-redis   → Session storage, cache
postgres          → User database, configurations, policies
```

### Container Details

```bash
# View running Authentik containers
docker compose ps | grep authentik

# Check resource usage
docker stats authentik-server authentik-worker authentik-redis
```

### Database Schema

```bash
# Connect to database
docker compose exec postgres psql -U authentik -d authentik

# List tables
\dt

# View users
SELECT username, email, is_active FROM auth_user;
```

## How Forward Auth Works

### Request Flow

```
1. User requests: https://grafana.antoineglacet.com
2. Traefik receives request
3. Traefik calls Authentik: GET http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
4. Authentik checks session:
   - Valid session → returns 200 + user headers
   - No session → returns 302 redirect to login
5. If 200: Traefik forwards request to Grafana with headers
   If 302: User sent to Authentik login page
6. After login, Authentik redirects back to original URL
```

### Middleware Configuration

Defined in `authentik-server` labels in `docker-compose.yml`:

```yaml
labels:
  # ForwardAuth middleware
  - "traefik.http.middlewares.authentik.forwardauth.address=http://authentik-server:9000/outpost.goauthentik.io/auth/traefik"
  - "traefik.http.middlewares.authentik.forwardauth.trustForwardHeader=true"
  - "traefik.http.middlewares.authentik.forwardauth.authResponseHeaders=authorization,X-authentik-username,X-authentik-groups,X-authentik-email,X-authentik-name,X-authentik-uid,X-authentik-jwt,X-authentik-meta-jwks,X-authentik-meta-outpost,X-authentik-meta-provider,X-authentik-meta-app,X-authentik-meta-version"
```

### Applying to Services

Add this label to any service in `docker-compose.yml`:

```yaml
labels:
  - "traefik.http.routers.SERVICE.middlewares=authentik@docker"
```

## Protected Services

### Services with Authentik Auth

These services require Authentik login:

- **Dashboards**: Grafana, Homepage, Glances
- **Management**: Traefik Dashboard, AdGuard Home
- **Media**: Sonarr, Radarr, Bazarr, Prowlarr, Transmission, Calibre Web
- **Utilities**: Zigbee2MQTT, Duplicati, Syncthing, SiYuan

### Services WITHOUT Authentik

These services use their own authentication:

- **Plex**: Native authentication (Authentik breaks many Plex clients)
- **Home Assistant**: Built-in user management
- **Prometheus**: Internal only (no external exposure)

### Why Some Services Skip Authentik

**Plex:**
- Mobile apps don't support forward auth
- Smart TVs/game consoles can't handle redirects
- Plex has robust built-in authentication

**Home Assistant:**
- Needs direct access for automations
- Mobile app requires native auth
- Companion app integration

## User Management

### Initial Setup

First user created becomes admin:

```bash
# After first startup, visit:
# https://authentik.antoineglacet.com

# Create admin account:
# - Username: admin
# - Email: your@email.com
# - Password: (strong password)
```

### Creating Users

1. **Via Admin UI:**
   - Navigate to: Directory → Users
   - Click: Create
   - Fill in: Username, Name, Email
   - Set: Active, groups
   - Optional: Set password or send invitation

2. **Bulk Import:**
   - Directory → Users → Import
   - Upload CSV with: username, email, name

### Managing Groups

Groups control access to applications:

```
1. Directory → Groups → Create
2. Name: "Media Admins"
3. Add users to group
4. Assign group to applications via Policies
```

### Password Policies

Configure in:
- System → Policies → Create → Password Policy
- Set: Min length, complexity, expiry

### MFA (Multi-Factor Authentication)

Enable for users:

1. **As admin:**
   - Directory → Users → Select user → Enroll
   - Choose: TOTP, WebAuthn, etc.

2. **As user:**
   - User settings → MFA Devices → Enroll

## Grafana OAuth Integration

Grafana uses Authentik as OAuth2 provider for seamless SSO.

### Setup in Authentik

1. **Create Provider:**
   - Applications → Providers → Create
   - Type: OAuth2/OpenID Provider
   - Name: `grafana-oauth`
   - Client Type: Confidential
   - Redirect URIs: `https://grafana.antoineglacet.com/login/generic_oauth`
   - Scopes: `openid profile email`
   - Save and note: Client ID, Client Secret

2. **Create Application:**
   - Applications → Applications → Create
   - Name: `Grafana`
   - Slug: `grafana`
   - Provider: `grafana-oauth`
   - Launch URL: `https://grafana.antoineglacet.com`

### Configure Grafana

Add to `.env`:

```bash
GF_AUTH_GENERIC_OAUTH_ENABLED=true
GF_AUTH_GENERIC_OAUTH_NAME=Authentik
GF_AUTH_GENERIC_OAUTH_CLIENT_ID=<client-id-from-authentik>
GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=<client-secret-from-authentik>
GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email
GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://authentik.antoineglacet.com/application/o/authorize/
GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://authentik.antoineglacet.com/application/o/token/
GF_AUTH_GENERIC_OAUTH_API_URL=https://authentik.antoineglacet.com/application/o/userinfo/
GF_AUTH_SIGNOUT_REDIRECT_URL=https://authentik.antoineglacet.com/application/o/grafana/end-session/
GF_AUTH_OAUTH_AUTO_LOGIN=true  # Skip Grafana login screen
GF_SERVER_ROOT_URL=https://grafana.antoineglacet.com
```

Restart Grafana:

```bash
docker compose restart grafana
```

### Role Mapping

Map Authentik groups to Grafana roles:

```bash
# In .env:
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=contains(groups[*], 'Grafana Admins') && 'Admin' || contains(groups[*], 'Grafana Editors') && 'Editor' || 'Viewer'
```

Then in Authentik:
1. Create groups: `Grafana Admins`, `Grafana Editors`
2. Assign users to groups

## Monitoring

### Health Checks

```bash
# Check Authentik server is responding
curl -I https://authentik.antoineglacet.com/-/health/live/

# Check worker is processing tasks
docker compose logs authentik-worker | grep -i "processing\|completed"

# Check Redis connection
docker compose exec authentik-redis redis-cli ping
# Should return: PONG
```

### Logs

```bash
# Server logs (auth attempts, errors)
docker compose logs -f authentik-server

# Worker logs (background tasks)
docker compose logs -f authentik-worker

# Filter for errors
docker compose logs authentik-server | grep -i error

# Filter for failed logins
docker compose logs authentik-server | grep -i "failed\|invalid"
```

### Metrics

Authentik exposes metrics at:
- https://authentik.antoineglacet.com/metrics

```bash
# View metrics
curl https://authentik.antoineglacet.com/metrics

# Scrape with Prometheus (add to prometheus.yml):
scrape_configs:
  - job_name: 'authentik'
    static_configs:
      - targets: ['authentik-server:9000']
    metrics_path: '/metrics'
```

### Database Health

```bash
# Check PostgreSQL is healthy
docker compose exec postgres pg_isready -U authentik -d authentik

# View active sessions
docker compose exec postgres psql -U authentik -d authentik -c "SELECT COUNT(*) FROM django_session WHERE expire_date > NOW();"

# View user count
docker compose exec postgres psql -U authentik -d authentik -c "SELECT COUNT(*) FROM authentik_core_user WHERE is_active=true;"
```

### Redis Health

```bash
# Check memory usage
docker compose exec authentik-redis redis-cli INFO memory

# View active connections
docker compose exec authentik-redis redis-cli CLIENT LIST

# Check key count
docker compose exec authentik-redis redis-cli DBSIZE
```

## Troubleshooting

### Login Issues

#### Can't login - "Invalid credentials"

```bash
# 1. Verify user exists and is active
docker compose exec postgres psql -U authentik -d authentik -c "SELECT username, is_active FROM authentik_core_user WHERE username='admin';"

# 2. Reset password via CLI
docker compose exec authentik-server ak create_admin_group

# 3. Check logs for details
docker compose logs authentik-server | grep -i "authentication failed"
```

#### Redirect loop

```bash
# 1. Clear browser cookies for *.antoineglacet.com

# 2. Check Grafana ROOT_URL matches Traefik route
docker compose exec grafana env | grep ROOT_URL
# Should match: https://grafana.antoineglacet.com

# 3. Verify OAuth redirect URI in Authentik
# Should be: https://grafana.antoineglacet.com/login/generic_oauth

# 4. Check forward auth header trust
docker inspect authentik-server | jq '.[0].Config.Labels' | grep trustForwardHeader
```

#### Session expires too quickly

```bash
# Adjust session timeout in Authentik:
# System → Settings → General → Session duration
# Default: 30 days

# Or via environment:
# Add to docker-compose.yml:
environment:
  - AUTHENTIK_SESSION_LIFETIME=2592000  # 30 days in seconds
```

### Service Access Issues

#### 502 Bad Gateway

```bash
# 1. Check Authentik server is running
docker compose ps authentik-server

# 2. Check health endpoint
curl -I https://authentik.antoineglacet.com/-/health/live/

# 3. Verify PostgreSQL is healthy
docker compose exec postgres pg_isready -U authentik

# 4. Check logs
docker compose logs authentik-server --tail=50
```

#### User can't access service after login

```bash
# 1. Check user is in allowed group for application
# Authentik Admin → Applications → [App] → Policy Bindings

# 2. Verify user groups
# Directory → Users → [User] → Groups

# 3. Check policy evaluation
# System → Events → Logs → Filter by user

# 4. Test with admin user
# If admin works, issue is permissions
```

### Database Issues

#### Database connection failed

```bash
# 1. Check PostgreSQL is running
docker compose ps postgres

# 2. Verify credentials in .env
grep AUTHENTIK_POSTGRESQL .env

# 3. Test connection
docker compose exec authentik-server python -c "import os; from django.db import connection; connection.ensure_connection(); print('Connected')"

# 4. Check postgres logs
docker compose logs postgres
```

#### Migration errors

```bash
# Run migrations manually
docker compose exec authentik-server ak migrate

# Check migration status
docker compose exec authentik-server ak showmigrations
```

### Performance Issues

#### Slow authentication

```bash
# 1. Check Redis latency
docker compose exec authentik-redis redis-cli --latency

# 2. Check PostgreSQL slow queries
docker compose exec postgres psql -U authentik -d authentik -c "SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"

# 3. Increase worker count
# Edit docker-compose.yml:
command: worker --concurrency 4
```

#### High memory usage

```bash
# Check memory usage
docker stats authentik-server

# Set memory limit in docker-compose.yml:
deploy:
  resources:
    limits:
      memory: 768M
```

### Recovery

#### Locked out of admin account

```bash
# Create recovery key
docker compose exec authentik-server ak create_recovery_key 10 akadmin

# Output will be a URL like:
# https://authentik.antoineglacet.com/recovery/use-token/?token=xxxxx

# Visit URL to set new password
```

#### Reset to defaults

```bash
# ⚠️ WARNING: This deletes all users, flows, policies!

# 1. Stop Authentik
docker compose stop authentik-server authentik-worker

# 2. Drop database
docker compose exec postgres psql -U postgres -c "DROP DATABASE authentik;"
docker compose exec postgres psql -U postgres -c "CREATE DATABASE authentik OWNER authentik;"

# 3. Clear Redis
docker compose exec authentik-redis redis-cli FLUSHALL

# 4. Start and migrate
docker compose start authentik-server authentik-worker
docker compose logs -f authentik-server

# 5. Create new admin user
# Visit: https://authentik.antoineglacet.com
```

### Debugging OAuth

#### OAuth login fails

```bash
# 1. Check redirect URI matches exactly
# Authentik: Applications → Providers → [provider] → Redirect URIs
# Should be: https://grafana.antoineglacet.com/login/generic_oauth

# 2. Verify client ID/secret
# Check .env matches Authentik provider

# 3. Test token endpoint
curl -X POST https://authentik.antoineglacet.com/application/o/token/ \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET"

# 4. Check Authentik events
# System → Events → Logs → Filter by application
```

### Common Mistakes

1. **Wrong database credentials**
   - Check `.env` matches actual database

2. **Redis password mismatch**
   - Ensure `AUTHENTIK_REDIS__PASSWORD` matches `redis-server --requirepass`

3. **Missing network**
   - Authentik needs `homelab` and `homelab_proxy` networks

4. **OAuth redirect URI typo**
   - Must match exactly (including trailing slash)

5. **Session timeout too short**
   - Users logged out frequently → increase session lifetime

### Debug Mode

Enable for detailed logs:

```yaml
# In docker-compose.yml:
environment:
  - AUTHENTIK_LOG_LEVEL=debug
```

Restart:

```bash
docker compose restart authentik-server authentik-worker
docker compose logs -f authentik-server
```

**Remember to disable after debugging!**
