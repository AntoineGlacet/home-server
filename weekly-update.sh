#!/usr/bin/env bash
# file used as root cron for weekly update of whole server
set -euo pipefail

# home server directory
HOMESERVER="${HOMESERVER:-/home/antoine/home-server}"
COMPOSE_FILE="${HOMESERVER}/docker-compose.yml"
ENV_FILE="${HOMESERVER}/.env"
HELPERS_FILE="${HOMESERVER}/lib/compose.sh"
LOG_FILE="/var/tmp/cron.logtest"
SKIP_APT_UPDATES="${SKIP_APT_UPDATES:-0}"

log_msg() {
  local now
  now=$(date)
  printf '[%s]\t%s\n' "$now" "$*" | tee -a "${LOG_FILE}"
}

log_cmd() {
  local now
  now=$(date)
  log_msg "$*"
  "$@" 2>&1 | awk -v now="${now}" '{ printf("[%s]\t%s\n", now, $0) }' | tee -a "${LOG_FILE}"
}

if [[ ! -d "${HOMESERVER}" ]]; then
  log_msg "Error: HOMESERVER directory not found at ${HOMESERVER}"
  exit 1
fi

if [[ ! -f "${HELPERS_FILE}" ]]; then
  log_msg "Error: compose helper library not found at ${HELPERS_FILE}"
  exit 1
fi

# shellcheck source=/dev/null
source "${HELPERS_FILE}"

require_compose_stack "${COMPOSE_FILE}" "${ENV_FILE}" log_msg
ensure_compose_command log_msg

# update and upgrade all packages
if [[ "${SKIP_APT_UPDATES}" != "1" ]]; then
  log_cmd sudo apt update -q -y
  log_cmd sudo apt upgrade -q -y
else
  log_msg "Skipping apt package updates (SKIP_APT_UPDATES=${SKIP_APT_UPDATES})"
fi

# pull and restart all services defined in the root compose file
log_cmd "${COMPOSE[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull
log_cmd "${COMPOSE[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d --remove-orphans

# prune unused resources
if command -v docker >/dev/null 2>&1; then
  log_cmd docker system prune -f
fi

# restart for good measure
# if [ -f /var/run/reboot-required ]; then
#    sudo reboot -h now
# fi
