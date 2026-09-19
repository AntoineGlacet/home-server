# CRITICAL — security items

## 🔴 OPEN (found 2026-09-19): `SAMBA_PASSWORD` is still the leaked MQTT password

The 2026-06-08 rotation below fixed the MQTT side, but the **same plaintext string is
still live as `SAMBA_PASSWORD`** in the server's `.env`. It was committed to a public
GitHub repo and only later purged from history, so it must be treated as burned: forks,
clones and any cached view of the old objects may still have it.

Verified on the server 2026-09-19 (value confirmed by comparison, not reproduced here —
do not paste it into a tracked file):

- `.env` `SAMBA_PASSWORD` equals the string purged from history on 2026-06-08.
- It is visible in the running container's command line (`docker inspect samba`),
  because dperson/samba takes `-u "user;password"` as an argument.
- The share it guards is **all of `/media/data`** (5.5 TB) mounted **read-write**
  (`-s "data;/data;yes;no;no;all"`, i.e. browsable, not read-only, guests denied).
- Samba listens on `0.0.0.0:445` and `0.0.0.0:139`, so it is reachable from the whole
  LAN *and* from wg-easy VPN clients. It is **not** port-forwarded at the router
  (only TCP 80/443 and UDP 51820 are), so this is not internet-exposed.

Decision 2026-09-19: documented, not rotated — deliberate, since rotating breaks every
saved SMB credential on the Windows clients.

### To fix later
1. Generate a new password; set `SAMBA_PASSWORD` in the server `.env` (gitignored).
2. `docker compose up -d samba` to recreate with the new argument.
3. Re-enter the credential on each SMB client (Windows stores it per-share).
4. Optional hardening while in there: bind the ports to the LAN interface rather than
   `0.0.0.0` (`ports: ["10.13.89.90:445:445/tcp", ...]`) so VPN clients cannot reach it,
   and consider a read-only share for anything that does not need writes.

Related: [`docs/troubleshooting.md`](docs/troubleshooting.md), the MQTT entry below.

## ✅ RESOLVED (2026-09-19): Stopped seeding 11 fake-video malware droppers

`downloads/complete` held 11 files of ~1.2 GB each named like TV episodes but ending in
`.exe`/`.scr` (`Silo S03E02 … .exe`, `Rick.and.Morty.S09E09….scr`, `Cape.Fear.S01E07….exe`,
…) — the standard fake-video dropper campaign. All 11 were **registered in Transmission and
being seeded**, so the box was distributing them.

Harmless on the server itself (never executed on Linux), but they sat inside the Samba
share above, which is browsable and writable from every LAN and VPN client — one
double-click from a Windows machine is the whole attack.

Removed with `transmission-remote --remove-and-delete` on 2026-09-19. Checks done first:
every file had a link count of 1, so none was hardlinked into the Plex library (Sonarr had
correctly refused to import them), and the four legitimate torrents that merely *contain* a
99-byte `RARBG_DO_NOT_MIRROR.exe` were excluded by matching on the torrent name, not a
recursive file search. Reclaimed ~12 GB.

Worth re-checking after any indexer change: `find /media/data/downloads -type f \
\( -iname '*.exe' -o -iname '*.scr' \) -size +100M`.

## ✅ RESOLVED (2026-06-08): Committed MQTT password rotated + purged from history

The `hass` MQTT password was rotated everywhere (mosquitto `users.db`, Home Assistant
`.storage`, and the gitignored `.env` via z2m's `ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD` override),
the plaintext removed from the tracked `configuration.yaml`, and the old value scrubbed from
all git history with `git filter-repo` + force-push (verified 0 occurrences). Note: z2m has no
`!secret` feature (that's Home Assistant) — its creds come from `.env` env-overrides, and z2m
does not write them back into `configuration.yaml`. Original plan kept below for reference.

<details><summary>Original plan (done)</summary>

## 🔴 Committed MQTT password (`hass` / plaintext) in git history

`config/zigbee2mqtt/configuration.yaml` contains a plaintext MQTT password that is
**tracked in git and present in history** (introduced ~commit `d1b9a0a`). The same
credential is reused across the smart-home stack, so rotating it is a coordinated,
*live* change — get it wrong and Zigbee + Home Assistant automations drop.

### Where the credential is used (footprint, verified on the server)
- `config/zigbee2mqtt/configuration.yaml` — **tracked** (the committed secret).
- `config/zigbee2mqtt/configuration_backup_v1|v2|v3.yaml` — untracked local backups (also contain it).
- `config/homeassistant/.storage/core.config_entries` — **Home Assistant's** MQTT integration uses it.
- mosquitto auth: `allow_anonymous false`, `password_file /mosquitto/data/users.db` (user `hass`).

### Agreed plan (decision: rotate **and** purge history)
1. Generate a new password. Update, in lockstep:
   - mosquitto `users.db`: `docker exec <mosquitto> mosquitto_passwd -b /mosquitto/data/users.db hass <NEW>`
   - zigbee2mqtt: move to gitignored `config/zigbee2mqtt/secrets.yaml` + reference `!secret mqtt_password` in `configuration.yaml`
   - Home Assistant: edit `.storage/core.config_entries` (**back it up first**, stop HA during edit)
2. Restart mosquitto → zigbee2mqtt → HA. **Verify** both reconnect (logs) before continuing. Roll back from backups on failure.
3. Commit the `!secret` change (removes plaintext from the current file).
4. **History purge:** rewrite history to scrub the password from all past commits of
   `configuration.yaml` (e.g. `git filter-repo`), **force-push** to GitHub, and
   `git reset --hard` the laptop + server clones to the rewritten history.
   - ⚠️ Step 4 rewrites shared history and is the irreversible-on-remote part.
5. Delete the untracked `configuration_backup_v*.yaml` files (old password, now invalid).

### Safety notes
- Steps 1–3 are reversible via the `.storage` backup.
- Even without the purge, rotating (step 1) makes the leaked password useless — do the
  rotation first, verify the smart home is healthy, then do the purge.

</details>

---

## Other known backlog (lower priority — from the code review)
- Schedule the postgres backup cron (currently not scheduled); confirm rotation works.
- Add healthchecks to traefik / authentik-server / authentik-redis / nordlynx / adguard
  (so autoheal + `depends_on: service_healthy` actually function).
- cAdvisor `privileged: true` — likely droppable.
- Postgres has no memory limit; `POSTGRES_PASSWORD_SUPERUSER:-password` weak default.
- ddclient `kanku.dev` block fails every cycle (token lacks that zone) — fix or remove.
- Optional: remove the now-dangling `docs.antoineglacet.com` Cloudflare DNS record.
