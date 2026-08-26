#!/usr/bin/env bash
#
# root-maintenance.sh -- the parts of the 2026-08-26 maintenance pass that need
# root. Everything else was applied through docker/compose and is already live.
#
# Run it on the server:
#     sudo /home/antoine/home-server/scripts/root-maintenance.sh
#
# Each step is independent and idempotent; re-running is safe. Steps announce
# themselves and can be skipped with the flags below.
#
#   --skip-lvm        do not grow the root logical volume
#   --skip-docker     do not write /etc/docker/daemon.json (avoids a daemon reload)
#   --skip-journal    do not vacuum the systemd journal
#   --skip-timer      do not install the postgres backup timer
#   --skip-apt        do not apply package updates
#   --skip-dpkg       do not purge removed-but-configured packages
#
set -euo pipefail

GROW_BY="${GROW_BY:-60G}"      # root LV currently 100G of a 235G PV
JOURNAL_KEEP="${JOURNAL_KEEP:-500M}"
REPO_DIR=/home/antoine/home-server

SKIP_LVM=0 SKIP_DOCKER=0 SKIP_JOURNAL=0 SKIP_TIMER=0 SKIP_APT=0 SKIP_DPKG=0
for a in "$@"; do
  case "$a" in
    --skip-lvm) SKIP_LVM=1 ;;
    --skip-docker) SKIP_DOCKER=1 ;;
    --skip-journal) SKIP_JOURNAL=1 ;;
    --skip-timer) SKIP_TIMER=1 ;;
    --skip-apt) SKIP_APT=1 ;;
    --skip-dpkg) SKIP_DPKG=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

[[ "$(id -u)" == 0 ]] || { echo "must run as root" >&2; exit 1; }

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

say "Before"
df -h / | tail -1

# --- 1. grow the root logical volume -----------------------------------------
# / was at 95%. Container logs (the real cause) are now capped, but the PV has
# ~135G unallocated, so there is no reason for / to stay at 100G.
if [[ "$SKIP_LVM" == 0 ]]; then
  say "Growing root LV by ${GROW_BY}"
  vgs
  if lvextend -L "+${GROW_BY}" /dev/ubuntu-vg/ubuntu-lv; then
    # ext4 grows online; no unmount, no downtime.
    resize2fs /dev/ubuntu-vg/ubuntu-lv
    note "grown"
  else
    note "lvextend declined (already grown, or not enough free extents) -- continuing"
  fi
  df -h / | tail -1
fi

# --- 2. docker log defaults ---------------------------------------------------
# Belt and braces: docker-compose.yml now caps every service, but a container
# started outside compose would still log without limit.
if [[ "$SKIP_DOCKER" == 0 ]]; then
  say "Setting docker daemon log defaults"
  if [[ -f /etc/docker/daemon.json ]]; then
    note "/etc/docker/daemon.json already exists -- leaving it alone:"
    cat /etc/docker/daemon.json
  else
    install -d -m 0755 /etc/docker
    cat >/etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
JSON
    note "written; applies to containers created from now on"
    # A reload is enough for the default to take effect on new containers, and
    # unlike `restart` it does not touch anything already running.
    systemctl reload docker || note "reload failed; run: systemctl restart docker (restarts containers)"
  fi
fi

# --- 3. journal ---------------------------------------------------------------
if [[ "$SKIP_JOURNAL" == 0 ]]; then
  say "Vacuuming systemd journal to ${JOURNAL_KEEP}"
  journalctl --disk-usage
  journalctl --vacuum-size="${JOURNAL_KEEP}"
  # Keep it bounded from here on rather than vacuuming again in six months.
  if ! grep -q '^SystemMaxUse=' /etc/systemd/journald.conf 2>/dev/null; then
    sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
    grep -q '^SystemMaxUse=' /etc/systemd/journald.conf || echo 'SystemMaxUse=500M' >>/etc/systemd/journald.conf
    systemctl restart systemd-journald
    note "SystemMaxUse=500M set"
  else
    note "SystemMaxUse already configured"
  fi
fi

# --- 4. postgres backup timer -------------------------------------------------
if [[ "$SKIP_TIMER" == 0 ]]; then
  say "Installing the postgres backup timer"
  install -m 0644 "${REPO_DIR}/config/systemd/home-server-pg-backup.service" /etc/systemd/system/
  install -m 0644 "${REPO_DIR}/config/systemd/home-server-pg-backup.timer"   /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now home-server-pg-backup.timer
  systemctl list-timers home-server-pg-backup.timer --no-pager
  note "verify a real run with: systemctl start home-server-pg-backup.service"
  note "then: journalctl -u home-server-pg-backup.service -n 40"
fi

# --- 5. package updates -------------------------------------------------------
if [[ "$SKIP_APT" == 0 ]]; then
  say "Applying package updates"
  apt-get update
  # Includes krb5 security updates and docker-ce 29.6.2 -> 29.7.2. Upgrading
  # docker-ce restarts the daemon, and therefore every container.
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
  apt-get -y autoremove --purge
  apt-get clean
  if [[ -f /var/run/reboot-required ]]; then
    note "REBOOT REQUIRED:"
    cat /var/run/reboot-required.pkgs 2>/dev/null | sed 's/^/      /'
  else
    note "no reboot required"
  fi
fi

# --- 6. dpkg leftovers --------------------------------------------------------
if [[ "$SKIP_DPKG" == 0 ]]; then
  say "Purging removed-but-configured packages"
  mapfile -t rc < <(dpkg -l | awk '$1=="rc" {print $2}')
  if (( ${#rc[@]} )); then
    note "purging ${#rc[@]} package(s)"
    dpkg --purge "${rc[@]}" || note "some purges failed -- not fatal"
  else
    note "none"
  fi
fi

# --- 7. disk health (read-only, was unverifiable without root) ----------------
say "SMART health"
for d in /dev/sda /dev/sdb; do
  echo "--- $d"
  smartctl -H "$d" 2>/dev/null | grep -Ei 'SMART overall|result' || echo "    smartctl unavailable"
  smartctl -A "$d" 2>/dev/null | grep -Ei \
    'Reallocated_Sector|Current_Pending|Offline_Uncorrectable|Power_On_Hours|Temperature_Celsius|Wear_Leveling|Media_Wearout|Percent_Lifetime' \
    | sed 's/^/    /'
done

say "After"
df -h / /media/data | tail -2
docker ps --format '{{.Names}} {{.Status}}' | grep -ci 'up' | xargs -I{} echo "containers up: {}"

say "Done"
