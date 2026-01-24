# Hugo Documentation Site

This directory contains the Hugo static site generator configuration for serving the home server documentation.

## Structure

```
hugo-docs/
├── config.toml           # Hugo configuration
├── content/              # Content directory (copied from ../docs/ during build)
│   ├── _index.md        # Landing page
│   └── docs/            # Documentation sections
│       ├── operations/
│       ├── infrastructure/
│       ├── monitoring/
│       ├── troubleshooting/
│       ├── deployment/
│       └── planning/
├── themes/docsy/         # Docsy theme
├── public/               # Generated static site (served by nginx)
└── README.md            # This file
```

## Building the Site

```bash
# From repository root:
./scripts/build-docs.sh
```

This builds the static HTML site to `hugo-docs/public/`.

## Local Preview

```bash
cd hugo-docs

# Start Hugo dev server
docker run --rm -it \
  -v $(pwd):/src \
  -p 1313:1313 \
  -u $(id -u):$(id -g) \
  hugomods/hugo:exts \
  hugo server --bind 0.0.0.0

# Visit http://localhost:1313
```

## Updating Documentation

1. **Edit markdown files** in `docs/` directory (source of truth)
2. **Rebuild**: `./scripts/build-docs.sh` (copies files from `docs/` and builds site)
3. **Commit**: Both source docs and built site
4. **Deploy**: `docker compose restart docs-site`

**Note**: The build script automatically copies markdown files from the `docs/` directory into the Hugo content structure before building.

## Theme

Uses [Docsy](https://www.docsy.dev/) - a Hugo theme for technical documentation.

### Theme Dependencies

Docsy requires:
- Hugo Extended (for SCSS support)
- PostCSS and dependencies (installed via npm in themes/docsy)

These are already installed. If you need to reinstall:

```bash
cd themes/docsy
npm install
```

## Deployment

The built static site in `public/` is served by an nginx container:

- **Service**: `docs-site` in `docker-compose.yml`
- **URL**: https://docs.antoineglacet.com
- **Protected by**: Authentik forward authentication
- **Memory**: ~5-10MB (nginx serving static files)

## Configuration

### Hugo Config (`config.toml`)

Key settings:
- Theme: Docsy
- Base URL: https://docs.antoineglacet.com
- Minimal UI (no git info, simple footer)
- Search enabled
- Syntax highlighting

### Content Organization

Content is organized by copying from the main `docs/` directory during build:

```bash
docs/operating.md   → hugo-docs/content/docs/operations/operating.md (copied during build)
docs/traefik.md     → hugo-docs/content/docs/infrastructure/traefik.md (copied during build)
# etc.
```

This keeps markdown files in one place (`docs/`) while allowing Hugo to organize them for the site. The build script handles the copying automatically.

## Troubleshooting

### Build fails with "module not found"

```bash
cd themes/docsy
npm install
```

### Permission issues

The build script runs Hugo in Docker with your user ID to avoid permission issues. If you still see permission errors:

```bash
docker run --rm -v $(pwd):/work -w /work alpine chown -R $(id -u):$(id -g) public/
```

### Theme updates

To update the Docsy theme:

```bash
cd themes/docsy
git pull origin main
npm install
cd ../..
./scripts/build-docs.sh
```

## Resource Usage

- **Build time**: ~2-3 seconds
- **Generated size**: ~2MB
- **Runtime memory**: ~5-10MB (nginx)
- **CPU**: Negligible (static files)
