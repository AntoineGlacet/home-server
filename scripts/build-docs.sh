#!/usr/bin/env bash
set -euo pipefail

echo "🔨 Building Hugo documentation site..."
echo ""

cd /home/antoine/home-server

# Copy content files from docs/ to hugo-docs/content/docs/
echo "📄 Copying content files..."
cp -f docs/traefik.md hugo-docs/content/docs/infrastructure/
cp -f docs/authentik.md hugo-docs/content/docs/infrastructure/
cp -f docs/operating.md hugo-docs/content/docs/operations/
cp -f docs/QUICK_START.md hugo-docs/content/docs/operations/
cp -f docs/PERFORMANCE_OPTIMIZATION.md hugo-docs/content/docs/operations/
cp -f docs/performance-tuning.md hugo-docs/content/docs/operations/
cp -f docs/monitoring.md hugo-docs/content/docs/monitoring/
cp -f docs/grafana-setup.md hugo-docs/content/docs/monitoring/
cp -f docs/troubleshooting.md hugo-docs/content/docs/troubleshooting/
cp -f docs/hugo-site-setup.md hugo-docs/content/docs/deployment/
cp -f docs/post-commit-steps.md hugo-docs/content/docs/deployment/
cp -f docs/deployment/*.md hugo-docs/content/docs/deployment/
cp -f docs/planning/*.md hugo-docs/content/docs/planning/

echo "✓ Content files copied"
echo ""

# Build with Hugo using Docker (use extended version for SCSS support)
docker run --rm \
  -v $(pwd):/src \
  -w /src/hugo-docs \
  hugomods/hugo:exts \
  hugo --minify --cleanDestinationDir

echo ""
echo "✓ Documentation built successfully"
echo "  Output: hugo-docs/public/"
echo ""
echo "To preview locally:"
echo "  cd hugo-docs"
echo "  docker run --rm -it -v \$(pwd):/src -p 1313:1313 -u \$(id -u):\$(id -g) klakegg/hugo:0.111.3-ext-alpine server"
echo ""
echo "To deploy:"
echo "  git add hugo-docs/public/ && git commit -m 'docs: rebuild site'"
echo "  docker compose restart docs-site"
