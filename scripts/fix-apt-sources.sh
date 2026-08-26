#!/usr/bin/env bash
#
# fix-apt-sources.sh -- clean up apt sources left behind by the jammy -> noble
# release upgrade.
#
# Two separate problems, both latent rather than actively broken:
#
#   1. /etc/apt/sources.list still carries the jammy (22.04) Ubuntu archives
#      alongside the noble (24.04) ones in sources.list.d/ubuntu.sources.
#      Nothing is currently installed from them -- noble always won the version
#      comparison -- but they are live sources: apt would take a jammy package
#      the moment jammy happened to carry a higher version, and jammy standard
#      support ends April 2027, after which they serve stale security data.
#
#   2. sources.list.d/docker.list points at jammy, so all 6 Docker packages are
#      22.04 builds on a 24.04 host. Docker publishes a noble repo with the same
#      upstream versions, and dpkg orders the noble build above the jammy one, so
#      switching is an ordinary upgrade.
#
# Usage (as root, on the server):
#     sudo /home/antoine/home-server/scripts/fix-apt-sources.sh
#         Rewrites sources, runs apt update, then REPORTS what would change.
#
#     sudo /home/antoine/home-server/scripts/fix-apt-sources.sh --apply-upgrade
#         Same, then actually upgrades. Note: upgrading docker-ce restarts the
#         Docker daemon and therefore every container, so pick your moment.
#
set -euo pipefail

APPLY=0
[[ "${1:-}" == "--apply-upgrade" ]] && APPLY=1
[[ "${1:-}" =~ ^(-h|--help)$ ]] && { sed -n '2,28p' "$0"; exit 0; }
[[ "$(id -u)" == 0 ]] || { echo "must run as root" >&2; exit 1; }

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/apt-sources-backup-$STAMP
mkdir -p "$BACKUP"

say "Backing up current apt config to $BACKUP"
cp -a /etc/apt/sources.list "$BACKUP/" 2>/dev/null || true
cp -a /etc/apt/sources.list.d "$BACKUP/" 2>/dev/null || true
note "done"

# --- 1. neutralise the legacy jammy Ubuntu archives ---------------------------
say "Commenting out jammy entries in /etc/apt/sources.list"
if grep -qE '^[[:space:]]*deb.*[[:space:]]jammy' /etc/apt/sources.list 2>/dev/null; then
  # Comment rather than delete, so the original intent stays readable on disk.
  sed -i -E 's|^([[:space:]]*deb.*[[:space:]]jammy)|# disabled (noble host, see fix-apt-sources.sh): \1|' \
    /etc/apt/sources.list
  note "commented $(grep -c 'disabled (noble host' /etc/apt/sources.list) line(s)"
else
  note "none found -- already clean"
fi

# --- 2. point the docker repo at noble ---------------------------------------
say "Pointing the Docker repo at noble"
if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
  if grep -q 'jammy' /etc/apt/sources.list.d/docker.list; then
    sed -i 's/\bjammy\b/noble/g' /etc/apt/sources.list.d/docker.list
    note "rewritten:"
    sed 's/^/      /' /etc/apt/sources.list.d/docker.list
  else
    note "already noble"
  fi
else
  note "no docker.list -- skipping"
fi

# Left over from do-release-upgrade; it is not read by apt but it is misleading.
if [[ -f /etc/apt/sources.list.d/docker.list.distUpgrade ]]; then
  mv /etc/apt/sources.list.d/docker.list.distUpgrade "$BACKUP/"
  note "moved stale docker.list.distUpgrade into the backup"
fi

# --- 3. refresh and report ----------------------------------------------------
say "apt update"
apt-get update

say "Suites apt now sees"
grep -rhoE '(noble|jammy)[a-z-]*' /etc/apt/sources.list /etc/apt/sources.list.d/*.list \
     /etc/apt/sources.list.d/*.sources 2>/dev/null \
  | grep -v '^#' | sort | uniq -c | sort -rn | sed 's/^/    /'

say "Pending changes"
apt-get -s upgrade 2>/dev/null | grep -E '^(Inst|Conf|Remv)' | sed 's/^/    /' || note "none"

if [[ "$APPLY" == 1 ]]; then
  say "Applying upgrade (this restarts the Docker daemon and all containers)"
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
  say "Docker packages now installed"
  dpkg -l 'docker*' containerd.io 2>/dev/null | awk '/^ii/ {printf "    %-32s %s\n", $2, $3}'
  say "Containers"
  sleep 15
  docker ps --format '{{.Names}} {{.Status}}' | wc -l | xargs -I{} note "{} running"
else
  say "Not applying"
  note "Re-run with --apply-upgrade to install the noble Docker builds."
  note "That restarts the Docker daemon and therefore every container."
fi

say "Done -- rollback: cp -a $BACKUP/sources.list /etc/apt/ && cp -a $BACKUP/sources.list.d /etc/apt/"
