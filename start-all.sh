#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env"

# shellcheck source=lib/compose.sh
source "${ROOT_DIR}/lib/compose.sh"

require_compose_stack "${COMPOSE_FILE}" "${ENV_FILE}"
ensure_compose_command

"${COMPOSE[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d --remove-orphans
