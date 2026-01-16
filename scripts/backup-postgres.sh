#!/usr/bin/env bash
set -euo pipefail

# PostgreSQL Backup Script
# Creates compressed backups of all databases with rotation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./data/postgres-backups}"
RETENTION_DAYS=7
CONTAINER_NAME="postgres"
POSTGRES_USER="${POSTGRES_SUPERUSER:-postgres}"

# Databases to back up
DATABASES=(
  "authentik"
  "postgres"  # System database
)

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Create backup directory
create_backup_dir() {
  if [[ ! -d "${BACKUP_DIR}" ]]; then
    log_info "Creating backup directory: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
  fi
}

# Check if Docker container is running
check_container() {
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "PostgreSQL container '${CONTAINER_NAME}' is not running"
    exit 1
  fi
  log_success "PostgreSQL container is running"
}

# Backup a single database
backup_database() {
  local db_name="$1"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${BACKUP_DIR}/${db_name}_${timestamp}.sql.gz"
  
  log_info "Backing up database: ${db_name}"
  
  # Perform backup with pg_dump and compress
  if docker exec "${CONTAINER_NAME}" pg_dump \
    -U "${POSTGRES_USER}" \
    -d "${db_name}" \
    --clean \
    --if-exists \
    --no-owner \
    --no-acl \
    2>/dev/null | gzip > "${backup_file}"; then
    
    # Check if backup file was created and is not empty
    if [[ -f "${backup_file}" && -s "${backup_file}" ]]; then
      local size
      size=$(du -h "${backup_file}" | cut -f1)
      log_success "Backup created: ${backup_file} (${size})"
    else
      log_error "Backup file is empty or missing: ${backup_file}"
      rm -f "${backup_file}"
      return 1
    fi
  else
    log_error "Failed to backup database: ${db_name}"
    rm -f "${backup_file}"
    return 1
  fi
}

# Backup all databases
backup_all_databases() {
  local success_count=0
  local fail_count=0
  
  log_info "Starting backup of ${#DATABASES[@]} database(s)"
  echo ""
  
  for db in "${DATABASES[@]}"; do
    if backup_database "${db}"; then
      ((success_count++))
    else
      ((fail_count++))
    fi
    echo ""
  done
  
  log_info "Backup summary: ${success_count} successful, ${fail_count} failed"
}

# Clean up old backups
rotate_backups() {
  log_info "Rotating backups (keeping last ${RETENTION_DAYS} days)"
  
  local deleted_count=0
  
  # Find and delete backups older than retention period
  while IFS= read -r -d '' backup_file; do
    rm -f "${backup_file}"
    log_info "Deleted old backup: $(basename "${backup_file}")"
    ((deleted_count++))
  done < <(find "${BACKUP_DIR}" -name "*.sql.gz" -type f -mtime +${RETENTION_DAYS} -print0 2>/dev/null)
  
  if (( deleted_count > 0 )); then
    log_success "Deleted ${deleted_count} old backup(s)"
  else
    log_info "No old backups to delete"
  fi
}

# List recent backups
list_backups() {
  echo ""
  log_info "Recent backups:"
  
  if [[ -d "${BACKUP_DIR}" ]]; then
    # Find all backups and list them sorted by date
    local backup_count=0
    
    while IFS= read -r backup_file; do
      local size
      local age
      size=$(du -h "${backup_file}" | cut -f1)
      age=$(stat -c '%y' "${backup_file}" | cut -d' ' -f1-2)
      echo "  • $(basename "${backup_file}") - ${size} - ${age}"
      ((backup_count++))
    done < <(find "${BACKUP_DIR}" -name "*.sql.gz" -type f | sort -r | head -10)
    
    if (( backup_count == 0 )); then
      log_warning "No backups found in ${BACKUP_DIR}"
    else
      echo ""
      log_info "Total backup size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
    fi
  else
    log_warning "Backup directory does not exist: ${BACKUP_DIR}"
  fi
}

# Print header
print_header() {
  echo "═══════════════════════════════════════"
  echo "  PostgreSQL Backup Script"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "═══════════════════════════════════════"
  echo ""
}

# Main execution
main() {
  print_header
  
  # Check if we're in the right directory
  if [[ ! -f "docker-compose.yml" ]]; then
    log_error "docker-compose.yml not found. Please run this script from the home-server directory"
    exit 1
  fi
  
  check_container
  echo ""
  
  create_backup_dir
  echo ""
  
  backup_all_databases
  echo ""
  
  rotate_backups
  echo ""
  
  list_backups
  
  echo ""
  echo "═══════════════════════════════════════"
  log_success "Backup process completed"
  echo "═══════════════════════════════════════"
}

# Restoration instructions
print_restore_help() {
  cat <<'EOF'

Restoration Instructions:
═════════════════════════

To restore a database from backup:

  1. Stop dependent services:
     docker compose stop authentik-server authentik-worker

  2. Restore the database:
     gunzip -c data/postgres-backups/authentik_YYYYMMDD_HHMMSS.sql.gz | \
       docker exec -i postgres psql -U postgres -d authentik

  3. Restart services:
     docker compose start authentik-server authentik-worker

Full restoration example:

  # List available backups
  ls -lh data/postgres-backups/

  # Restore specific backup
  docker compose stop authentik-server authentik-worker
  gunzip -c data/postgres-backups/authentik_20260116_120000.sql.gz | \
    docker exec -i postgres psql -U postgres -d authentik
  docker compose start authentik-server authentik-worker

  # Verify services are healthy
  docker compose ps
  docker compose logs authentik-server --tail=50

EOF
}

# Run main function
main

# Show restore help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  print_restore_help
fi

exit 0
