#!/bin/bash
################################################################################
# Reset Grafana Alerts Database
# Created: 2026-01-17
#
# Purpose: Clear all alert rules from Grafana database to allow clean provisioning
# WARNING: This will delete ALL existing alert rules!
################################################################################

set -euo pipefail

echo "⚠️  WARNING: This will delete ALL existing Grafana alert rules!"
echo "This is necessary to allow clean provisioning from YAML files."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Stopping Grafana..."
docker stop grafana

echo "Clearing alert rules from Grafana database..."
# The alert rules are stored in Grafana's SQLite database
# We'll delete the database and let Grafana recreate it with fresh provisioning

GRAFANA_DATA="/home/antoine/home-server/data/grafana"

if [ -f "$GRAFANA_DATA/grafana.db" ]; then
    echo "Backing up current database..."
    cp "$GRAFANA_DATA/grafana.db" "$GRAFANA_DATA/grafana.db.backup-$(date +%Y%m%d-%H%M%S)"
    
    echo "Removing alert rules from database..."
    docker run --rm -v "$GRAFANA_DATA:/grafana" alpine sh -c "
        apk add --no-cache sqlite
        sqlite3 /grafana/grafana.db 'DELETE FROM alert_rule;'
        sqlite3 /grafana/grafana.db 'DELETE FROM alert_rule_version;'
        sqlite3 /grafana/grafana.db 'DELETE FROM alert_configuration;'
        sqlite3 /grafana/grafana.db 'DELETE FROM ngalert_configuration;'
    "
    
    echo "✓ Alert rules cleared from database"
else
    echo "Grafana database not found at $GRAFANA_DATA/grafana.db"
    exit 1
fi

echo ""
echo "Starting Grafana..."
docker start grafana

echo ""
echo "✓ Done! Grafana will now provision alerts from YAML files."
echo "Check logs: docker logs grafana"
