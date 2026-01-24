# Documentation Index

Complete documentation for the home server setup.

## Quick Links

- **New here?** Start with [../README.md](../README.md) and [QUICK_START.md](QUICK_START.md)
- **Need help?** Check [troubleshooting.md](troubleshooting.md)
- **Daily operations?** See [operating.md](operating.md)

## Core Guides

### Operations & Infrastructure

| Guide | Description |
| --- | --- |
| **[operating.md](operating.md)** | Day-to-day operations, Docker commands, helper scripts, backups |
| **[traefik.md](traefik.md)** | Reverse proxy, TLS certificates, routing, service exposure |
| **[authentik.md](authentik.md)** | SSO, authentication, user management, OAuth integration |
| **[monitoring.md](monitoring.md)** | Prometheus, Grafana, Loki, alerting, dashboards |
| **[troubleshooting.md](troubleshooting.md)** | Common issues and solutions for all components |

### Performance

| Guide | Description |
| --- | --- |
| **[QUICK_START.md](QUICK_START.md)** | Quick fix for SSH lag and memory pressure |
| **[PERFORMANCE_OPTIMIZATION.md](PERFORMANCE_OPTIMIZATION.md)** | Comprehensive kernel tuning and optimization |
| **[performance-tuning.md](performance-tuning.md)** | Additional performance tuning notes |

### Configuration

| Guide | Description |
| --- | --- |
| **[grafana-setup.md](grafana-setup.md)** | Grafana configuration and dashboard setup |
| **[post-commit-steps.md](post-commit-steps.md)** | Steps to take after committing changes |

## Deployment

Documentation about deployment processes and migrations.

| Document | Description |
| --- | --- |
| **[DEPLOYMENT_CHECKLIST.md](deployment/DEPLOYMENT_CHECKLIST.md)** | Pre-deployment verification checklist |
| **[DEPLOYMENT_NOTES.md](deployment/DEPLOYMENT_NOTES.md)** | Deployment history and notes |
| **[ALERTING_MIGRATION.md](deployment/ALERTING_MIGRATION.md)** | Alertmanager to Grafana migration guide |

See [deployment/](deployment/) for all deployment-related documentation.

## Planning & Status

Current state and future plans.

| Document | Description |
| --- | --- |
| **[IMPLEMENTATION_STATUS.md](planning/IMPLEMENTATION_STATUS.md)** | Current state of all services |
| **[NEXT_STEPS.md](planning/NEXT_STEPS.md)** | Planned improvements and roadmap |
| **[SECURITY_REMEDIATION.md](planning/SECURITY_REMEDIATION.md)** | Security hardening notes |

See [planning/](planning/) for all planning documentation.

## Documentation by Topic

### Getting Started

1. Read [../README.md](../README.md) for overview
2. Follow [QUICK_START.md](QUICK_START.md) for initial setup
3. Review [operating.md](operating.md) for basic operations
4. Check [deployment/DEPLOYMENT_CHECKLIST.md](deployment/DEPLOYMENT_CHECKLIST.md) before deploying

### Networking & Access

- [traefik.md](traefik.md) - Reverse proxy and HTTPS
- [authentik.md](authentik.md) - Authentication and SSO
- [operating.md#networking](operating.md#networking) - Network architecture

### Monitoring & Logs

- [monitoring.md](monitoring.md) - Complete monitoring stack guide
- [grafana-setup.md](grafana-setup.md) - Grafana-specific configuration
- [monitoring.md#alerting](monitoring.md#alerting) - Setting up alerts

### Troubleshooting

- [troubleshooting.md](troubleshooting.md) - Start here for problems
- [QUICK_START.md](QUICK_START.md) - Performance issues
- [traefik.md#troubleshooting](traefik.md#troubleshooting) - Traefik-specific issues
- [authentik.md#troubleshooting](authentik.md#troubleshooting) - Auth issues
- [monitoring.md](monitoring.md) - Monitoring issues

### Advanced Topics

- [PERFORMANCE_OPTIMIZATION.md](PERFORMANCE_OPTIMIZATION.md) - Deep dive on performance
- [deployment/ALERTING_MIGRATION.md](deployment/ALERTING_MIGRATION.md) - Alerting system migration
- [planning/SECURITY_REMEDIATION.md](planning/SECURITY_REMEDIATION.md) - Security considerations

## Contributing to Documentation

When adding new documentation:

1. **Core guides** → Place in `docs/` root
2. **Deployment-related** → Place in `docs/deployment/`
3. **Planning/status** → Place in `docs/planning/`
4. Update this index
5. Update [../README.md](../README.md) if it's a major guide

Keep documentation:
- **Focused** - One topic per file
- **Practical** - Include examples and commands
- **Current** - Update when things change
- **Linked** - Cross-reference related docs
