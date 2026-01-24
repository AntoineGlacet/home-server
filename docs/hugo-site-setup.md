---
title: "Hugo Documentation Site - Setup Guide"
weight: 2
description: "Hugo static site implementation for serving documentation"
---

This document describes the Hugo static site implementation for serving documentation.

## Quick Start

```bash
# Start the docs site
docker compose up -d docs-site

# View logs
docker compose logs -f docs-site

# Visit: https://docs.antoineglacet.com
```

## What Was Implemented

### Documentation Site

- **Static Site Generator**: Hugo with Docsy theme
- **Build Strategy**: Build locally, commit generated HTML
- **Serving**: nginx:alpine container (~5-10MB RAM)
- **URL**: https://docs.antoineglacet.com
- **Authentication**: Protected by Authentik
- **Content**: Symlinks to existing `docs/` markdown files

### Architecture

```
docs/ (source of truth)
  ↓ symlinked by
hugo-docs/content/
  ↓ built by
hugo-docs/public/ (static HTML, 2MB)
  ↓ served by
nginx:alpine container
  ↓ exposed via
Traefik + Authentik
  ↓
https://docs.antoineglacet.com
```

## File Organization

### Source Structure

All documentation **remains** in the `docs/` directory:

```
docs/
├── README.md
├── operating.md
├── traefik.md
├── authentik.md
├── monitoring.md
├── troubleshooting.md
├── QUICK_START.md
├── PERFORMANCE_OPTIMIZATION.md
├── deployment/
│   ├── DEPLOYMENT_CHECKLIST.md
│   ├── DEPLOYMENT_NOTES.md
│   └── ALERTING_MIGRATION.md
└── planning/
    ├── IMPLEMENTATION_STATUS.md
    ├── NEXT_STEPS.md
    └── SECURITY_REMEDIATION.md
```

### Hugo Site Structure

```
hugo-docs/
├── config.toml              # Hugo configuration
├── content/
│   ├── _index.md           # Landing page
│   └── docs/
│       ├── operations/      # Symlinks to docs/operating.md, etc.
│       ├── infrastructure/  # Symlinks to docs/traefik.md, etc.
│       ├── monitoring/
│       ├── troubleshooting/
│       ├── deployment/
│       └── planning/
├── themes/docsy/           # Docsy theme (459MB, for builds only)
├── public/                 # Generated site (2MB, committed)
└── README.md
```

## Updating Documentation

### Workflow

1. **Edit source**: Modify files in `docs/` directory
2. **Rebuild**: Run `./scripts/build-docs.sh`
3. **Commit**: Both source and generated site
4. **Deploy**: Restart container if running

### Example

```bash
# Edit documentation
vim docs/traefik.md

# Rebuild Hugo site
./scripts/build-docs.sh

# Commit changes
git add docs/traefik.md hugo-docs/public/
git commit -m "docs: update Traefik certificate guide"

# Restart service (if already running)
docker compose restart docs-site
```

### Local Preview

Preview changes before committing:

```bash
cd hugo-docs

# Start Hugo dev server
docker run --rm -it \
  -v $(pwd):/src \
  -p 1313:1313 \
  hugomods/hugo:exts \
  hugo server --bind 0.0.0.0

# Visit: http://localhost:1313
# Live reload enabled - changes appear instantly
```

## Build Script

**Location**: `scripts/build-docs.sh`

**What it does**:
1. Runs Hugo in Docker container (no local install needed)
2. Builds static HTML to `hugo-docs/public/`
3. Uses `hugomods/hugo:exts` image (includes extended Hugo + dependencies)
4. Minifies output
5. Cleans destination directory

**Usage**:
```bash
./scripts/build-docs.sh
```

**Output**:
```
🔨 Building Hugo documentation site...
✓ Documentation built successfully
  Output: hugo-docs/public/
```

## Docker Service

### Configuration

Service defined in `docker-compose.yml`:

```yaml
docs-site:
  image: nginx:alpine
  container_name: docs-site
  restart: unless-stopped
  volumes:
    - ./hugo-docs/public:/usr/share/nginx/html:ro
  deploy:
    resources:
      limits:
        memory: 32M
      reservations:
        memory: 8M
  networks:
    - homelab_proxy
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.docs.rule=Host(`docs.${TRAEFIK_DOMAIN}`)"
    - "traefik.http.routers.docs.entrypoints=websecure"
    - "traefik.http.routers.docs.tls.certresolver=cloudflare"
    - "traefik.http.routers.docs.middlewares=authentik@docker"
    - "traefik.http.services.docs.loadbalancer.server.port=80"
```

### Resource Usage

- **Image size**: ~7MB (nginx:alpine)
- **Runtime memory**: ~5-10MB actual usage
- **CPU**: Negligible (serving static files)
- **Disk**: 2MB (generated site)

### Operations

```bash
# Start service
docker compose up -d docs-site

# Stop service
docker compose stop docs-site

# View logs
docker compose logs -f docs-site

# Restart after rebuild
docker compose restart docs-site

# Check status
docker compose ps docs-site
```

## Theme: Docsy

### About

- **Theme**: [Docsy](https://www.docsy.dev/)
- **Type**: Google-style technical documentation
- **Features**: Search, navigation, mobile-responsive, dark mode
- **License**: Apache 2.0

### Theme Files

Located in `hugo-docs/themes/docsy/`:

- **Size**: 459MB (includes node_modules for builds)
- **Only needed**: During build time
- **Not needed**: At runtime (nginx serves static HTML)

### Theme Dependencies

Docsy requires npm packages for building. Already installed:

```bash
cd hugo-docs/themes/docsy
npm install
```

This creates:
- `node_modules/` (ignored in git)
- `themes/github.com/` (Bootstrap, Font Awesome)

## Customization

### Site Configuration

Edit `hugo-docs/config.toml`:

```toml
# Change title
title = "Your Title"

# Change description
[params]
description = "Your description"

# Customize UI
[params.ui]
navbar_logo = false
sidebar_menu_compact = true

# Add external links
[[params.links.user]]
  name = "Homepage"
  url = "https://homepage.antoineglacet.com"
```

### Landing Page

Edit `hugo-docs/content/_index.md`:

```markdown
---
title: "Home Server Documentation"
---

{{< blocks/cover title="Your Title" >}}
Your description here
{{< /blocks/cover >}}

{{% blocks/section %}}
Add custom sections...
{{% /blocks/section %}}
```

### Colors & Styling

Docsy uses Bootstrap. Override in `hugo-docs/assets/scss/_variables_project.scss`:

```scss
// Custom primary color
$primary: #007bff;

// Custom link color
$link-color: #0056b3;
```

Then rebuild.

## Homepage Integration

Added to `config/homepage/services.yaml`:

```yaml
- infrastructure:
    - Documentation:
        icon: mdi-book-open-variant
        href: https://docs.antoineglacet.com
        description: Server documentation & guides
```

## Troubleshooting

### Build Fails

**Issue**: "module not found" error

**Solution**:
```bash
cd hugo-docs/themes/docsy
npm install
cd ../..
./scripts/build-docs.sh
```

### Permission Issues

**Issue**: `public/` directory owned by root

**Solution**:
```bash
docker run --rm -v $(pwd):/work -w /work alpine \
  chown -R $(id -u):$(id -g) hugo-docs/public/
```

### Service Won't Start

**Issue**: Container exits immediately

**Solution**:
```bash
# Check logs
docker compose logs docs-site

# Verify public directory exists and has content
ls -la hugo-docs/public/

# Rebuild if needed
./scripts/build-docs.sh

# Restart
docker compose up -d docs-site
```

### 404 Not Found

**Issue**: Traefik shows 404 for docs site

**Check**:
1. Service is running: `docker compose ps docs-site`
2. Public directory exists: `ls hugo-docs/public/`
3. Traefik sees service: Visit traefik dashboard
4. DNS resolves: `nslookup docs.antoineglacet.com`

### Authentik Loop

**Issue**: Redirect loop when accessing site

**Solution**: See [Authentik troubleshooting](authentik.md#troubleshooting)

## Benefits

### Minimal Overhead

- **Static HTML**: No runtime processing
- **Small footprint**: 2MB site, ~5-10MB RAM
- **Fast**: Instant page loads
- **Reliable**: nginx is rock-solid

### Single Source of Truth

- **Markdown stays in `docs/`**: One place to edit
- **Symlinks**: Hugo references existing files
- **No duplication**: Same markdown for Git and web

### Professional Appearance

- **Docsy theme**: Used by Kubernetes, TensorFlow, etc.
- **Search built-in**: Client-side, no server needed
- **Mobile-friendly**: Responsive design
- **Dark mode**: Automatic theme switching

### Easy Updates

- **Simple workflow**: Edit markdown, rebuild, commit
- **Preview locally**: Hugo dev server with live reload
- **Zero-build deploy**: Built site committed to repo

## Future Improvements

Optional enhancements:

1. **Version selector**: If you want to version docs
2. **Custom logo**: Add server logo to navbar
3. **Analytics**: Add Google Analytics if desired
4. **Custom domain**: Use subdomain or custom domain
5. **CI/CD**: Auto-build on git push (GitHub Actions)

## References

- [Hugo Documentation](https://gohugo.io/documentation/)
- [Docsy Theme](https://www.docsy.dev/)
- [Hugo in Docker](https://github.com/hugomods/docker)
- [nginx:alpine](https://hub.docker.com/_/nginx)
