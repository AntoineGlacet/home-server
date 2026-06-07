#!/usr/bin/env bash
#
# deploy.sh — push the local source-of-truth to the home server and apply it.
#
# Flow (LAN-only, manual):
#   1. Verify the local working tree is clean and on the expected branch.
#   2. Push the branch to origin (GitHub).
#   3. SSH to the server, fast-forward its checkout, and run `start-all.sh`
#      (docker compose up -d --remove-orphans).
#   4. Optionally run the server health check.
#
# The server keeps its own untracked files (.env, runtime config/, data/) —
# git only touches tracked files, so secrets and live state are never clobbered.
# A non-fast-forward (i.e. someone edited on the server) aborts the deploy
# loudly instead of overwriting; reconcile on the server first.
#
# Usage:
#   ./deploy.sh                 # push + deploy current branch
#   ./deploy.sh --no-push       # skip the GitHub push, just pull+apply on server
#   ./deploy.sh --health        # also run scripts/health-check.sh afterwards
#
# Overridable via env: REMOTE_HOST, REMOTE_DIR, BRANCH
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-optiplex}"
REMOTE_DIR="${REMOTE_DIR:-/home/antoine/home-server}"
BRANCH="${BRANCH:-master}"

DO_PUSH=1
DO_HEALTH=0
for arg in "$@"; do
  case "$arg" in
    --no-push) DO_PUSH=0 ;;
    --health)  DO_HEALTH=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

cd "$(dirname "${BASH_SOURCE[0]}")"

# 1. Local sanity ----------------------------------------------------------
current_branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$current_branch" == "$BRANCH" ]] || die "On branch '$current_branch', expected '$BRANCH'. Checkout $BRANCH or set BRANCH=."
[[ -z "$(git status --porcelain)" ]] || die "Local working tree is dirty. Commit or stash before deploying."

local_sha="$(git rev-parse --short HEAD)"
say "Deploying $BRANCH @ $local_sha to ${REMOTE_HOST}:${REMOTE_DIR}"

# 2. Push to origin --------------------------------------------------------
if [[ "$DO_PUSH" == 1 ]]; then
  say "Pushing to origin/$BRANCH"
  git push origin "$BRANCH"
else
  say "Skipping push (--no-push)"
fi

# 3. Apply on the server ---------------------------------------------------
say "Updating server checkout and (re)starting changed containers"
ssh "$REMOTE_HOST" bash -se <<REMOTE
  set -euo pipefail
  cd "${REMOTE_DIR}"
  if [[ -n "\$(git status --porcelain --untracked-files=no)" ]]; then
    echo "xx Server has uncommitted changes to tracked files — aborting." >&2
    git status --short >&2
    echo "   Reconcile on the server (commit/discard) before deploying." >&2
    exit 1
  fi
  git fetch --quiet origin "${BRANCH}"
  git merge --ff-only "origin/${BRANCH}"
  ./start-all.sh
  echo "Now at: \$(git rev-parse --short HEAD)"
REMOTE

# 4. Health check ----------------------------------------------------------
if [[ "$DO_HEALTH" == 1 ]]; then
  say "Running health check"
  ssh "$REMOTE_HOST" "cd '${REMOTE_DIR}' && ./scripts/health-check.sh" || true
fi

say "Done."
