# Minabot

Automated clock-in/clock-out bot for the Minagine time management system.
Formerly a standalone project in `~/minabot` on the server; merged into the
home-server compose stack (July 2026) for simpler deploys and real monitoring.

## Overview

- Checks whether today is a working day in Minagine
- Clocks in and out at configured times with random variance (±`VARIANCE` min)
- Runs Selenium (headless Chrome) **on demand**: started ~5 min before each
  action via the docker socket, stopped right after, so it uses no RAM idle
- Rotates its own logs (logrotate, 50MB × 2)

## Architecture

Two services in the root `docker-compose.yml`:

| Service | Container | Role |
|---|---|---|
| `minabot` | `minabot` | cron + `script/main.py`, controls selenium via docker socket |
| `minabot-selenium` | `minabot-selenium` | headless Chrome, `restart: "no"`, started/stopped by minabot |

On container start, `cron.py` installs two cron jobs (clock-in/out time minus
2×variance). Each run: check working day → wait for the randomized target →
click the button → stop selenium. Cron output is tee'd to both
`/logs/cron_script.log` and the container stdout, so runs are visible in
`docker logs minabot` and in Loki/Grafana.

### Why the recreate path matters (June 2026 incident)

`weekly-update.sh` runs `docker system prune -f`, which deletes **stopped**
containers — and minabot-selenium is stopped by design between runs. In the
old standalone setup this deleted the selenium container and the bot's
recreate fallback was broken, silently killing the bot for two weeks.

Now:
- every `compose up -d` (deploy + weekly update, which runs *before* the
  prune) recreates/starts the container, and
- `main.py` can itself recreate it: the repo's `docker-compose.yml` and `.env`
  are mounted read-only at `/compose/`, and the image ships the compose
  plugin, so a missing container is rebuilt from the same compose definition
  (`docker compose -p <project> up -d --no-deps minabot-selenium`).

## Configuration

Secrets/schedule live in `minabot/script/.env` **on the server** (untracked,
covered by the repo's global `.env` gitignore — same pattern as the root
`.env`). Required keys:

```env
COMPANY=...            # Minagine company domain
ID=...                 # employee id
PASS=...               # password
CLOCK_IN_TIME=HH:MM
CLOCK_OUT_TIME=HH:MM
VARIANCE=5             # minutes; cron fires at target − 2×VARIANCE
SCRIPT_PATH=/script/main.py
LOGS_PATH=/logs
PYTHON_PATH=/usr/local/bin/python
TZ=Asia/Tokyo
```

Logs land in `data/minabot/logs/` on the server (untracked).

## Operations

```bash
docker logs -f minabot                 # cron setup + run output
docker exec minabot crontab -l         # verify schedule
docker ps -a | grep minabot            # selenium should be Exited between runs
```

Health: the `minabot` container has a `pgrep cron` healthcheck (autoheal
restarts it if cron dies). A Grafana alert (Loki) fires to Discord if no run
has completed in 26h.

Safe end-to-end test that never clicks a clock button (logs in and reads the
working-day sheet only):

```bash
docker exec minabot /usr/local/bin/python -c \
  "import sys; sys.path.insert(0, '/script'); import main; \
   print('working day:', main.check_if_working_day(main.env_vars)); main.stop_selenium()"
```

## Disclaimer

Personal automation for the owner's own Minagine account. Ensure use complies
with your organization's policies.
