# Photos — Immich (deferred, documented for the future)

> **Status:** not deployed. Captured 2026-06-28 while evaluating a Google Photos
> replacement. Revisit when the storage + RAM constraints below are resolved.

## Why Immich

[Immich](https://immich.app) is the closest self-hosted equivalent to Google
Photos. It is the only mature option that matches the one feature that actually
matters — **automatic background phone backup** — alongside a timeline, albums,
partner/shared albums, face recognition, map view, "memories," and ML-powered
search (natural-language + OCR text-in-image).

**Quality is equal-or-better than Google Photos.** Google's default "Storage
saver" tier *recompresses* photos and video. Immich stores **original files
untouched** at full resolution, including RAW and full-quality video. So there
is no quality loss — it's an upgrade.

## Why it was deferred (constraints on the OptiPlex 3050)

Measured 2026-06-28:

1. **Disk — the gating factor.** `/media/data` was at **90% full, ~534 GB free
   of 5.5 TB**. A full Google Photos library plus ongoing growth needs a real
   storage plan first (expand/replace the data drive, or dedicate a budget).
   Confirm the Google Photos library size before committing.
2. **RAM — tight.** Box runs ~5.2 GB used of 7.6 GB (~2.5 GB free). Immich adds
   the heaviest footprint of any candidate: `immich-server` + its own Postgres
   (with the `pgvector`/VectorChord extension) + Redis + a **machine-learning**
   container that can spike **1.5–3 GB** during the initial face/smart-search
   backfill. It will run but will swap during first import.

### Mitigations if/when revisited
- Cap or temporarily disable the `immich-machine-learning` container; use a
  smaller CLIP model; let ML jobs run slowly in the background.
- Give Immich its own Postgres rather than sharing the stack's (Immich pins a
  specific pgvector image and is picky about versions).
- Memory-limit every Immich container in compose, as the rest of the stack does.

## Integration notes (when building)

- **Do NOT put Immich behind Authentik forward-auth.** Like Plex, the Immich
  mobile app talks to the API directly and its own login handles auth — a
  forward-auth middleware breaks the app. Expose it via Traefik *without* the
  `authentik@docker` middleware.
- Traefik route would follow the existing pattern:
  `immich.${TRAEFIK_DOMAIN}` → `immich-server:2283`.
- Bind originals onto the big data drive (`${MEDIA}`-adjacent), not the system disk.

## Migration from Google Photos

1. Request a **Google Takeout** export of Google Photos (multi-archive; can be
   hundreds of GB — download to the data drive).
2. Import with [`immich-go`](https://github.com/simulot/immich-go), which
   reconstructs dates, albums, and geolocation from Google's JSON sidecars
   (Takeout itself strips/garbles some EXIF; immich-go repairs it from sidecars).

## Lighter alternative

**PhotoPrism** is lighter on RAM, but its phone-backup story is weak (relies on
WebDAV / third-party sync apps rather than a first-party auto-backup app), which
undercuts the main reason to leave Google Photos. Prefer Immich unless RAM is the
hard blocker.
