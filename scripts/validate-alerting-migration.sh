#!/bin/bash
################################################################################
# Validate Grafana Alerting Migration
# Created: 2026-01-17
#
# Purpose: Validate that the migration from Alertmanager to Grafana was successful
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

log_pass() {
    echo -e "${GREEN}✓${NC} $*"
    ((PASS++))
}

log_fail() {
    echo -e "${RED}✗${NC} $*"
    ((FAIL++))
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

################################################################################
# Check 1: Provisioning Files Exist
################################################################################

check_provisioning_files() {
    log_section "Checking Provisioning Files"
    
    local files=(
        "/home/antoine/home-server/config/grafana/provisioning/alerting/contactpoints.yml"
        "/home/antoine/home-server/config/grafana/provisioning/alerting/policies.yml"
        "/home/antoine/home-server/config/grafana/provisioning/alerting/templates.yml"
        "/home/antoine/home-server/config/grafana/provisioning/alerting/rules.yml"
    )
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            log_pass "Found: $(basename "$file")"
        else
            log_fail "Missing: $file"
        fi
    done
}

################################################################################
# Check 2: Docker Compose Updated
################################################################################

check_docker_compose() {
    log_section "Checking Docker Compose Configuration"
    
    # Check alertmanager is removed
    if ! grep -q "alertmanager:" ~/home-server/docker-compose.yml; then
        log_pass "alertmanager service removed from docker-compose.yml"
    else
        log_fail "alertmanager service still present in docker-compose.yml"
    fi
    
    # Check alertmanager-discord is removed
    if ! grep -q "alertmanager-discord:" ~/home-server/docker-compose.yml; then
        log_pass "alertmanager-discord service removed from docker-compose.yml"
    else
        log_fail "alertmanager-discord service still present in docker-compose.yml"
    fi
    
    # Check Grafana has unified alerting enabled
    if grep -q "GF_UNIFIED_ALERTING_ENABLED=true" ~/home-server/docker-compose.yml; then
        log_pass "Grafana unified alerting enabled in docker-compose.yml"
    else
        log_warn "GF_UNIFIED_ALERTING_ENABLED not explicitly set (should be true by default)"
    fi
    
    # Check Discord webhook env var
    if grep -q "DISCORD_WEBHOOK_URL=" ~/home-server/docker-compose.yml; then
        log_pass "Discord webhook URL passed to Grafana"
    else
        log_fail "Discord webhook URL not passed to Grafana"
    fi
}

################################################################################
# Check 3: Containers Not Running
################################################################################

check_containers() {
    log_section "Checking Container Status"
    
    # Check alertmanager is not running
    if ! docker ps --format '{{.Names}}' | grep -q "^alertmanager$"; then
        log_pass "alertmanager container not running"
    else
        log_fail "alertmanager container is still running"
    fi
    
    # Check alertmanager-discord is not running
    if ! docker ps --format '{{.Names}}' | grep -q "^alertmanager-discord$"; then
        log_pass "alertmanager-discord container not running"
    else
        log_fail "alertmanager-discord container is still running"
    fi
    
    # Check Grafana is running
    if docker ps --format '{{.Names}}' | grep -q "^grafana$"; then
        log_pass "Grafana container is running"
    else
        log_fail "Grafana container is NOT running"
    fi
}

################################################################################
# Check 4: Grafana API Checks
################################################################################

check_grafana_api() {
    log_section "Checking Grafana Alerting API"
    
    # Wait a bit for Grafana to fully start
    sleep 2
    
    # Check if Grafana is responsive
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health | grep -q "200"; then
        log_pass "Grafana API is responsive"
    else
        log_fail "Grafana API is not responsive"
        return
    fi
    
    # Check contact points (requires auth, so we'll check logs instead)
    log_info "For full API validation, check Grafana UI at: http://localhost:3000"
}

################################################################################
# Check 5: Grafana Logs
################################################################################

check_grafana_logs() {
    log_section "Checking Grafana Logs for Provisioning"
    
    # Check if provisioning succeeded
    if docker logs grafana 2>&1 | tail -100 | grep -q "provisioning"; then
        log_pass "Grafana provisioning logs found"
        
        # Look for specific provisioning messages
        local log_output=$(docker logs grafana 2>&1 | tail -200)
        
        if echo "$log_output" | grep -qi "contact.*point"; then
            log_pass "Contact point provisioning mentioned in logs"
        else
            log_warn "Contact point provisioning not clearly visible in recent logs"
        fi
        
        if echo "$log_output" | grep -qi "alert.*rule\|provisioning.*alert"; then
            log_pass "Alert rule provisioning mentioned in logs"
        else
            log_warn "Alert rule provisioning not clearly visible in recent logs"
        fi
    else
        log_warn "Could not find provisioning logs (may need to restart Grafana)"
    fi
    
    # Check for errors
    if docker logs grafana 2>&1 | tail -100 | grep -qi "error.*alert\|error.*provision"; then
        log_fail "Found errors in Grafana logs related to alerting/provisioning"
        echo ""
        echo -e "${RED}Recent errors:${NC}"
        docker logs grafana 2>&1 | tail -100 | grep -i "error.*alert\|error.*provision" | tail -5
    else
        log_pass "No alerting/provisioning errors in recent Grafana logs"
    fi
}

################################################################################
# Check 6: Prometheus Configuration
################################################################################

check_prometheus_config() {
    log_section "Checking Prometheus Configuration"
    
    # Check that alertmanager is removed from config
    if ! grep -q "alertmanagers:" ~/home-server/config/prometheus/prometheus.yml; then
        log_pass "Alertmanager configuration removed from Prometheus"
    else
        log_warn "Alertmanager configuration still present in Prometheus config"
    fi
}

################################################################################
# Check 7: Environment Variables
################################################################################

check_env_vars() {
    log_section "Checking Environment Variables"
    
    # Check if Discord webhook is set
    if [ -f ~/home-server/.env ] && grep -q "DISCORD_WEBHOOK_URL=" ~/home-server/.env; then
        log_pass "DISCORD_WEBHOOK_URL found in .env file"
        
        # Verify it's not empty
        local webhook=$(grep "DISCORD_WEBHOOK_URL=" ~/home-server/.env | cut -d'=' -f2)
        if [ -n "$webhook" ] && [ "$webhook" != "your-discord-webhook-url-here" ]; then
            log_pass "DISCORD_WEBHOOK_URL appears to be configured"
        else
            log_fail "DISCORD_WEBHOOK_URL is empty or placeholder"
        fi
    else
        log_fail "DISCORD_WEBHOOK_URL not found in .env file"
    fi
}

################################################################################
# Check 8: File Permissions
################################################################################

check_permissions() {
    log_section "Checking File Permissions"
    
    local alerting_dir="/home/antoine/home-server/config/grafana/provisioning/alerting"
    
    if [ -d "$alerting_dir" ]; then
        if [ -r "$alerting_dir" ] && [ -x "$alerting_dir" ]; then
            log_pass "Alerting directory is readable"
        else
            log_fail "Alerting directory has permission issues"
        fi
        
        # Check files are readable
        local readable=true
        for file in "$alerting_dir"/*.yml; do
            if [ -f "$file" ] && [ ! -r "$file" ]; then
                readable=false
                log_fail "File not readable: $(basename "$file")"
            fi
        done
        
        if [ "$readable" = true ]; then
            log_pass "All provisioning files are readable"
        fi
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    clear
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Grafana Alerting Migration Validation${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    check_provisioning_files
    check_docker_compose
    check_env_vars
    check_containers
    check_permissions
    check_prometheus_config
    check_grafana_api
    check_grafana_logs
    
    # Summary
    log_section "Validation Summary"
    echo ""
    echo -e "${GREEN}Passed checks: $PASS${NC}"
    echo -e "${RED}Failed checks: $FAIL${NC}"
    echo ""
    
    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✓ All checks passed!${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Open Grafana UI: http://localhost:3000"
        echo "2. Go to: Alerting → Contact points"
        echo "3. Click 'Test' on the Discord contact point"
        echo "4. Go to: Alerting → Alert rules"
        echo "5. Verify all 23 alert rules are present"
        echo ""
        return 0
    else
        echo -e "${RED}════════════════════════════════════════${NC}"
        echo -e "${RED}✗ Some checks failed${NC}"
        echo -e "${RED}════════════════════════════════════════${NC}"
        echo ""
        echo "Please review the failures above and:"
        echo "1. Check the migration documentation: ~/home-server/ALERTING_MIGRATION.md"
        echo "2. Review Grafana logs: docker logs grafana"
        echo "3. Verify docker-compose.yml changes"
        echo ""
        return 1
    fi
}

main "$@"
