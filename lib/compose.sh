#!/usr/bin/env bash

# Shared helpers for interacting with the project's Docker Compose stack.

_compose_default_reporter() {
  echo "$1" >&2
}

require_compose_stack() {
  local compose_file="$1"
  local env_file="$2"
  local reporter="${3:-_compose_default_reporter}"

  if [[ ! -f "${compose_file}" ]]; then
    "${reporter}" "Error: docker-compose.yml not found at ${compose_file}"
    return 1
  fi

  if [[ ! -f "${env_file}" ]]; then
    "${reporter}" "Error: .env not found at ${env_file}"
    return 1
  fi
}

find_compose() {
  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      COMPOSE=(docker compose)
      return 0
    fi
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
    return 0
  fi

  COMPOSE=()
  return 1
}

ensure_compose_command() {
  local reporter="${1:-_compose_default_reporter}"

  if find_compose; then
    return 0
  fi

  "${reporter}" "Error: docker compose or docker-compose is required but not installed."
  return 1
}
