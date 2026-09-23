---
title: "Photos — Immich"
weight: 7
description: "Self-hosted Google Photos replacement: deployment, first run, phone backup, Takeout migration, backups"
---

Immich is the stack's photo and video library, replacing Google Photos. It runs as
four containers in the **PHOTOS (IMMICH)** section of `docker-compose.yml` and is
reachable at **https://immich.antoineglacet.com** (web, and the server URL for the
mobile app).

> **Status:** deployed 2026-09-23 on Immich **v3.2.2**. The June 2026 deferral
> (below) was lifted because the library to migrate is ~15 GB, not hundreds.

## Table of Contents

- [Architecture](#architecture)
- [Why Immich](#why-immich)
- [First run (one time, you)](#first-run-one-time-you)
- [Phone backup](#phone-backup)
- [Migrating from Google Photos](#migrating-from-google-photos)
- [Authentication](#authentication)
- [Resources on the 8 GB box](#resources-on-the-8-gb-box)
- [Backups](#backups)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [History: the June 2026 deferral](#history-the-june-2026-deferral)

## Architecture

| Container | Image | Role | Where its state lives |
| --- | --- | --- | --- |
| `immich-server` | `ghcr.io/immich-app/immich-server:v3.2.2` | API + web UI + background jobs | Library bind mount `${IMMICH_UPLOAD_LOCATION}` → `/data` (data HDD) |
| `immich-machine-learning` | `ghcr.io/immich-app/immich-machine-learning:v3.2.2` | CLIP smart search, face detection, OCR | Named volume `immich_model_cache` (SSD) |
| `immich-postgres` | `ghcr.io/immich-app/postgres:14-vectorchord…` | Immich's **own** Postgres with vector extensions | Named volume `immich_postgres_data` (SSD) |
| `immich-redis` | `valkey/valkey:9` | Job queue | none (ephemeral) |

- **Networks:** `immich-server` is on `homelab` + `homelab_proxy`; the other three are
  `homelab`-only and never exposed.
- **Ingress:** Traefik router `immich` → `immich-server:2283`, TLS via the Cloudflare
  resolver, **no Authentik forward-auth** (see [Authentication](#authentication)).
- **Library layout** under `/media/data/immich/`: `upload/`, `library/`, `thumbs/`,
  `encoded-video/`, `profile/`, and `backups/` (Immich's own nightly DB dumps).
- **GPU:** `/dev/dri` is passed to `immich-server` for Quick Sync video transcoding,
  the same render node Plex gets. ML runs on CPU (the OpenVINO ML image is heavier and
  not worth it for this library size).
- **Do not** point Immich at the stack's shared `postgres` service. Immich pins a
  specific Postgres build with VectorChord/pgvecto.rs and refuses to start on anything
  else.

## Why Immich

Immich is the closest self-hosted equivalent to Google Photos and the only mature
option with a **first-party automatic phone backup** app, plus timeline, albums,
partner sharing, face recognition, map, memories, and natural-language search.

Quality is equal or better: Google's "Storage saver" tier recompresses uploads,
Immich stores **originals untouched** (RAW and full-quality video included).

PhotoPrism is lighter on RAM but has no real phone-backup story, which is the whole
point of leaving Google Photos.

## First run (one time, you)

1. Open https://immich.antoineglacet.com. The first visit shows **Getting Started**
   — create the admin account (this is a local Immich account; Authentik SSO is
   optional, see below).
2. **Tame the job queues for this box.** Administration → Settings → Job Settings:
   set *Smart Search*, *Face Detection*, *Facial Recognition* and *Video
   Transcoding* concurrency to **1**, everything else to 2. This is what keeps the
   first import from swapping the machine.
3. **Enable hardware transcoding.** Administration → Settings → Video Transcoding →
   Hardware Acceleration: **Quick Sync**. Leave the rest default.
4. **Homepage widget.** Logged in as the **admin** user: Account (top right) →
   *Account Settings* → *API Keys* → *New API Key*, name it `homepage`, tick only
   **`server.statistics`**. The widget calls `/api/server/statistics`, which Immich
   restricts to admins, so a key from a non-admin user fails even with that scope.
   Put the key in the server's `.env` as `IMMICH_API_KEY=…`, then
   `docker compose up -d homepage` so the container picks up the new variable.
   Until then the Immich card on Homepage shows an API error.
5. Optional: Administration → Settings → Server → set *External domain* to
   `https://immich.antoineglacet.com` so shared links are generated correctly.

## Phone backup

Install **Immich** from the Play Store (or GitHub releases via Obtainium:
`immich-app/immich`, the `app-*.apk` asset). Server URL:
`https://immich.antoineglacet.com`. Log in, pick the albums to back up (Camera,
Screenshots, WhatsApp…), enable background backup. No VPN required — this is one of
the few services published through Traefik without Authentik in front, so the app
works on mobile data.

## Migrating from Google Photos

Use [`immich-go`](https://github.com/simulot/immich-go), not the web uploader: Google
Takeout strips or garbles EXIF dates, and immich-go repairs them from Takeout's JSON
sidecars, recreates albums, and skips duplicates on re-runs.

**Installed:** `~/bin/immich-go` on the OptiPlex, v0.32.0 (static binary, no deps).
Staging directory: `/media/data/downloads/takeout/`.

> Google retired the Photos Library API for third-party clients, so Takeout is the
> only complete export path. There is no live sync.

### 1. Request the Takeout (you, ~hours to days)

At [takeout.google.com](https://takeout.google.com):

- **Deselect all**, then select **Google Photos** only.
- Under *All photo albums included*, leave everything ticked.
- Delivery: **send download link by email**; file type **.zip**; size **10 GB**.

Google emails a link when the archive is ready — minutes for a small library,
sometimes a day or more. **The links expire after 7 days.**

### 2. Get the archives onto the server

Download the parts on the laptop or PC, then drop them into the SMB share:

```
\\10.13.89.90\data\downloads\takeout        (Windows)
smb://10.13.89.90/data/downloads/takeout      (phone / Linux)
```

Do **not** unzip — immich-go reads the archives directly and needs the JSON
sidecars inside them. Check every part arrived (Google numbers them
`takeout-<date>-001.zip`, `-002`, …) before importing; a missing part means
missing photos.

### 3. Create the API key (you, in Immich)

Account Settings → API Keys → New API Key, name it `immich-go`. As the admin user,
the simplest is **Select all**; the minimum scopes otherwise are `asset.read`,
`asset.statistics`, `asset.update`, `asset.upload`, `asset.copy`, `asset.delete`,
`asset.download`, `album.create`, `album.read`, `albumAsset.create`, `server.about`,
`stack.create`, `tag.asset`, `tag.create`, `user.read`, plus `job.create` and
`job.read` for the `--admin-api-key` flag below (immich-go pauses background jobs
while it uploads).

### 4. Turn down the job concurrency first

Administration → Settings → Job Settings: set **Smart Search**, **Face Detection**,
**Facial Recognition** and **Video Transcoding** to **1**, Thumbnail Generation and
Metadata Extraction to **2**. Defaults (3–5) will thrash swap on this 8 GB box
during the import. Save before starting.

### 5. Dry run, then import

On the server (`ssh optiplex`):

```bash
export IMMICH_KEY='<the immich-go api key>'
cd /media/data/downloads/takeout

# Dry run first — reports what it would upload, touches nothing
~/bin/immich-go upload from-google-photos \
  --server https://immich.antoineglacet.com \
  --api-key "$IMMICH_KEY" \
  --admin-api-key "$IMMICH_KEY" \
  --concurrent-tasks 2 \
  --dry-run \
  takeout-*.zip

# Looks right? Same command without --dry-run, under tmux so an SSH drop
# doesn't kill it
tmux new -s immich-import
~/bin/immich-go upload from-google-photos \
  --server https://immich.antoineglacet.com \
  --api-key "$IMMICH_KEY" \
  --admin-api-key "$IMMICH_KEY" \
  --concurrent-tasks 2 \
  takeout-*.zip
# detach with Ctrl-b d, reattach with: tmux attach -t immich-import
```

Defaults worth knowing: albums are recreated (`--sync-albums`), archived photos and
partner photos are included, trashed photos are **not**. Add `--include-trashed` if
you want the bin too. `--concurrent-tasks 2` is deliberate — the default 4 is too
much for this box.

Re-running the same command is safe: immich-go asks the server what it already has
and skips duplicates, so an interrupted import resumes cleanly.

### 6. Watch it land

```bash
ssh optiplex 'docker stats --no-stream | grep immich; free -h | sed -n 2,3p'
```

Administration → Jobs in the web UI shows the queues draining: thumbnails and
metadata first, then Smart Search and Face Detection. For ~15 GB (a few thousand
assets) expect the upload in well under an hour and the ML backfill in one to three
hours at concurrency 1. It is fine to leave the ML queues running overnight.

### 7. Verify before trusting it

- Asset count roughly matches Google Photos (Google's own count is in the Photos
  settings page).
- Spot-check dates on old photos — this is what Takeout gets wrong and immich-go
  fixes, so it is the thing worth checking.
- Albums are present with sensible contents.
- A few videos play in the web UI and the mobile app.
- Faces appear under People once Face Detection finishes.

### 8. Only then, clean up

1. **Set up the off-site backup** (see [Backups](#backups)) — this is the point of
   no return: once Google is emptied, `/media/data/immich` on a single HDD is the
   only copy.
2. Delete the Takeout archives from `/media/data/downloads/takeout/`.
3. Revoke the `immich-go` API key.
4. Turn off Google Photos backup in the Google Photos app on the phone, and confirm
   the Immich app's background backup is on and has caught up.
5. Leave the Google library in place for a few weeks as a safety net before deleting
   anything there.

## Authentication

Immich is **not** behind the `authentik@docker` forward-auth middleware, for the same
reason Plex is not: the mobile app authenticates against `/api` itself and a
redirect-to-login in front of it breaks the app. Immich's own login handles access.

Optional single sign-on: Immich supports Authentik as an **OIDC** provider, which
gives you the Authentik login button on both web and mobile. Setup steps are in
[authentik.md → Immich OIDC Integration](authentik.md#immich-oidc-integration).

## Resources on the 8 GB box

Memory limits are set in compose and are deliberate:

| Container | Limit | Typical | Notes |
| --- | --- | --- | --- |
| `immich-server` | 1536M | ~700M RSS idle | API + microservices in one container. `docker stats` shows ~950 MiB because it counts page cache; cgroup anon was 715 MB right after first boot, so 1 GiB left no headroom for uploads or transcodes |
| `immich-machine-learning` | 1536M | ~200M idle | 1–1.3 GB with CLIP + face models loaded; `MACHINE_LEARNING_MODEL_TTL=120` unloads them after 2 min idle |
| `immich-postgres` | 512M | 100–200M | `shm_size: 128mb` as upstream requires |
| `immich-redis` | 128M | ~10M | |

Expect some swapping during the initial ML backfill; it stops when the jobs drain. The
Grafana rule **Container High Memory Usage** (> 1 GiB) may fire once for
`immich-machine-learning` during that window — that is expected, not a fault.

If the box is struggling, `docker compose stop immich-machine-learning` — everything
except new smart-search/face indexing keeps working — and start it again when the
queue can run overnight. Search on already-indexed assets is unaffected.

A 16 GB RAM upgrade would let ML stay resident permanently; it is not required.

## Backups

- **Database:** Immich dumps its own DB nightly to `/data/backups/` inside the
  library (`${IMMICH_UPLOAD_LOCATION}/backups/`), keeping 14 by default
  (Administration → Settings → Backup Settings). `scripts/backup-postgres.sh` only
  covers the shared stack Postgres, **not** Immich's — rely on Immich's dumps.
- **Library:** the originals in `${IMMICH_UPLOAD_LOCATION}` are **not** covered by
  Duplicati today (its source is `${HOMESERVER}` only) and the data drive is a single
  HDD. Leaving Google Photos means this directory is the only copy of the photos.
  **Add an off-site job before deleting anything from Google:** either a Duplicati
  job with `${IMMICH_UPLOAD_LOCATION}` as source and B2/Hetzner as destination, or a
  restic/rclone cron to the same. For ~15 GB the cost is negligible.
- **Restore** (upstream procedure): fresh containers, restore the latest SQL dump
  into `immich-postgres`, put the library back at `${IMMICH_UPLOAD_LOCATION}`, start
  `immich-server`. See https://docs.immich.app/administration/backup-and-restore.

## Upgrading

Immich moves fast and **does** ship breaking changes; releases marked with a warning
in the notes need a read before bumping. Procedure:

1. Read https://github.com/immich-app/immich/releases for every version between the
   pinned tag and the target. Look for "breaking", changed Postgres image, or new
   required env vars.
2. Bump **both** `immich-server` and `immich-machine-learning` tags together
   (they must match). Bump the Postgres/Valkey digests only if the release notes
   say so; the DB image is pinned by digest from the upstream compose.
3. `./deploy.sh`. The server migrates the DB on start; watch
   `docker compose logs -f immich-server` until "Immich Server is listening".

## Troubleshooting

```bash
docker compose logs -f immich-server              # startup, DB migrations, job errors
docker compose logs -f immich-machine-learning    # model downloads on first job
docker compose ps immich-server immich-postgres immich-redis immich-machine-learning
curl -s https://immich.antoineglacet.com/api/server/ping   # {"res":"pong"}
```

| Symptom | Likely cause / fix |
| --- | --- |
| Server restarts in a loop, log mentions `vectorchord` or `pgvecto.rs` | Wrong Postgres image or a version bump that requires a new DB image — check release notes. |
| Mobile app "Server is not reachable" but web works | Something put `authentik@docker` on the `immich` router. Remove it. |
| First ML job takes ages | Models (~1 GB) download into `immich_model_cache` on first use. One-time. |
| `immich-machine-learning` OOM-killed | Lower Smart Search / Face Detection concurrency to 1, or raise the limit temporarily. |
| Uploads of large videos fail | Traefik has no body-size middleware on this router; check the phone's network first. |
| Homepage card shows "API Error" | `IMMICH_API_KEY` not set in `.env` yet, or homepage not recreated after setting it. |

## History: the June 2026 deferral

Evaluated 2026-06-28 and deferred 2026-06-29 because the OptiPlex 3050 (8 GB, data
drive 90 % full) could not host Immich's ML stack **plus a full Google Photos library
of unknown size** on top of the existing 39-container stack. Revisit triggers were
RAM → 16 GB, a bigger data drive, or a smaller library. Re-evaluated 2026-09-23: the
library turned out to be ~15 GB total, so the disk concern disappeared and the RAM
concern became "cap the ML container and run the backfill once", which is how it is
deployed above.
