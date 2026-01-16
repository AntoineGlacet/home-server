#!/usr/bin/env bash
set -euo pipefail

# Backup Validation Script
# Verifies Duplicati backups are current and critical configs exist

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DUPLICATI_DATA_DIR="${DUPLICATI_DATA_DIR:-./data/duplicati}"
MIN_BACKUP_SIZE_MB=100
MAX_BACKUP_AGE_HOURS=24
CRITICAL_CONFIGS=(
  "docker-compose.yml"
  ".env.example"
  "config/prometheus/prometheus.yml"
  "config/traefik/letsencrypt/acme.json"
  "config/authentik"
)

# Exit codes
EXIT_SUCCESS=0
EXIT_WARNING=1
EXIT_CRITICAL=2

# Counters
WARNINGS=0
ERRORS=0

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $*"
  ((WARNINGS++))
}

log_error() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((ERRORS++))
}

print_header() {
  echo ""
  echo "═══════════════════════════════════════"
  echo "  Backup Validation Report"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "═══════════════════════════════════════"
  echo ""
}

check_duplicati_backup() {
  log_info "Checking Duplicati backup status..."
  
  # Check if Duplicati data directory exists
  if [[ ! -d "${DUPLICATI_DATA_DIR}" ]]; then
    log_error "Duplicati data directory not found: ${DUPLICATI_DATA_DIR}"
    return
  fi
  
  # Find most recent backup file
  local latest_backup
  latest_backup=$(find "${DUPLICATI_DATA_DIR}" -type f -name "*.sqlite" -o -name "*.dblock" 2>/dev/null | sort -r | head -1)
  
  if [[ -z "${latest_backup}" ]]; then
    log_warning "No backup files found in ${DUPLICATI_DATA_DIR}"
    log_info "Checking Duplicati database instead..."
    
    latest_backup=$(find "${DUPLICATI_DATA_DIR}" -type f -name "*.sqlite" 2>/dev/null | head -1)
    if [[ -z "${latest_backup}" ]]; then
      log_error "No Duplicati database found"
      return
    fi
  fi
  
  # Check backup age
  local backup_age_seconds
  backup_age_seconds=$(( $(date +%s) - $(stat -c %Y "${latest_backup}") ))
  local backup_age_hours=$(( backup_age_seconds / 3600 ))
  
  if (( backup_age_hours > MAX_BACKUP_AGE_HOURS )); then
    log_error "Last backup is ${backup_age_hours} hours old (threshold: ${MAX_BACKUP_AGE_HOURS}h)"
    log_info "Last backup: ${latest_backup}"
  else
    log_success "Last backup is ${backup_age_hours} hours old (within ${MAX_BACKUP_AGE_HOURS}h threshold)"
  fi
  
  # Check backup size
  local backup_size_mb
  backup_size_mb=$(du -sm "${DUPLICATI_DATA_DIR}" | cut -f1)
  
  if (( backup_size_mb < MIN_BACKUP_SIZE_MB )); then
    log_warning "Backup directory is only ${backup_size_mb}MB (expected >${MIN_BACKUP_SIZE_MB}MB)"
  else
    log_success "Backup directory size: ${backup_size_mb}MB (>${MIN_BACKUP_SIZE_MB}MB)"
  fi
}

check_critical_configs() {
  log_info "Checking critical configuration files..."
  
  for config in "${CRITICAL_CONFIGS[@]}"; do
    if [[ -e "${config}" ]]; then
      local size
      if [[ -d "${config}" ]]; then
        size=$(du -sh "${config}" | cut -f1)
        log_success "Directory exists: ${config} (${size})"
      else
        size=$(du -h "${config}" | cut -f1)
        log_success "File exists: ${config} (${size})"
      fi
    else
      log_error "Missing critical config: ${config}"
    fi
  done
}

check_env_file() {
  log_info "Checking .env file..."
  
  if [[ ! -f ".env" ]]; then
    log_error ".env file not found (required for docker-compose)"
    return
  fi
  
  # Check file permissions (should be 600 for security)
  local perms
  perms=$(stat -c %a ".env")
  
  if [[ "${perms}" == "600" ]]; then
    log_success ".env file has correct permissions (600)"
  else
    log_warning ".env file has permissions ${perms} (should be 600)"
    log_info "Fix with: chmod 600 .env"
  fi
  
  # Check for placeholder secrets
  if grep -q "change_me_" ".env" 2>/dev/null; then
    log_warning ".env contains 'change_me_' placeholders - secrets may not be configured"
    local count
    count=$(grep -c "change_me_" ".env")
    log_info "Found ${count} placeholder(s)"
  else
    log_success ".env appears to be configured (no placeholders found)"
  fi
}

check_docker_volumes() {
  log_info "Checking Docker volume backups..."
  
  # Check if Docker is running
  if ! docker info >/dev/null 2>&1; then
    log_warning "Docker is not running - cannot check volumes"
    return
  fi
  
  # List important volumes
  local volumes=(
    "postgres_data"
    "authentik_redis_data"
  )
  
  for vol in "${volumes[@]}"; do
    if docker volume inspect "${vol}" >/dev/null 2>&1; then
      log_success "Docker volume exists: ${vol}"
    else
      log_warning "Docker volume not found: ${vol}"
    fi
  done
}

check_backup_script_schedule() {
  log_info "Checking backup script schedule..."
  
  # Check if backup scripts exist
  if [[ -f "scripts/backup-postgres.sh" ]]; then
    log_success "PostgreSQL backup script exists"
  else
    log_warning "PostgreSQL backup script not found"
  fi
  
  # Check if cron is configured for weekly updates
  if crontab -l 2>/dev/null | grep -q "weekly-update.sh"; then
    log_success "Weekly update cron job is configured"
  else
    log_warning "Weekly update cron job not found"
    log_info "Consider adding to crontab: 0 3 * * 0 /home/antoine/home-server/weekly-update.sh"
  fi
}

print_summary() {
  echo ""
  echo "═══════════════════════════════════════"
  echo "  Validation Summary"
  echo "═══════════════════════════════════════"
  
  if (( ERRORS > 0 )); then
    echo -e "${RED}✗ CRITICAL:${NC} ${ERRORS} error(s) found"
  fi
  
  if (( WARNINGS > 0 )); then
    echo -e "${YELLOW}⚠ WARNING:${NC} ${WARNINGS} warning(s) found"
  fi
  
  if (( ERRORS == 0 && WARNINGS == 0 )); then
    echo -e "${GREEN}✓ SUCCESS:${NC} All checks passed"
  fi
  
  echo ""
  
  # Determine exit code
  if (( ERRORS > 0 )); then
    return ${EXIT_CRITICAL}
  elif (( WARNINGS > 0 )); then
    return ${EXIT_WARNING}
  else
    return ${EXIT_SUCCESS}
  fi
}

# Main execution
main() {
  print_header
  
  check_duplicati_backup
  echo ""
  
  check_critical_configs
  echo ""
  
  check_env_file
  echo ""
  
  check_docker_volumes
  echo ""
  
  check_backup_script_schedule
  
  print_summary
}

# Run main function
main
exit_code=$?

# Provide recommendations based on results
if (( exit_code == EXIT_CRITICAL )); then
  echo "Recommendations:"
  echo "  1. Check Duplicati service: docker compose ps duplicati"
  echo "  2. Review Duplicati logs: docker compose logs duplicati --tail=100"
  echo "  3. Verify backup destination is accessible"
  echo "  4. Run manual backup via Duplicati web UI"
elif (( exit_code == EXIT_WARNING )); then
  echo "Recommendations:"
  echo "  1. Review warnings above and address as needed"
  echo "  2. Consider increasing backup frequency if backups are old"
  echo "  3. Ensure all placeholders in .env are replaced with real values"
fi

exit ${exit_code}
