# CRITICAL — security items

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
