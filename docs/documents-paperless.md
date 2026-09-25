---
title: "Documents — Paperless-ngx"
weight: 8
description: "Personal admin documents: OCR'd, searchable, auto-filed; drop folder on Samba; import from Google Drive and Gmail"
---

Paperless-ngx holds personal admin papers — identity and residence documents,
contracts, payslips, bank and tax papers, insurance, receipts — OCR'd in French,
English and Japanese and searchable by content. It runs as two containers in the
**DOCUMENTS (PAPERLESS-NGX)** section of `docker-compose.yml` and is reachable at
**https://paperless.antoineglacet.com**.

> **Status:** deployed 2026-09-25 on Paperless-ngx **3.2.1**, single user.
> This repo is public: never put document names, numbers or contents in this file.

## Table of Contents

- [Architecture](#architecture)
- [Login](#login)
- [Adding documents](#adding-documents)
- [How documents are organised](#how-documents-are-organised)
- [Importing from Google Drive and Gmail](#importing-from-google-drive-and-gmail)
- [Resources](#resources)
- [Backups](#backups)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)

## Architecture

| Container | Image | Role | State |
| --- | --- | --- | --- |
| `paperless` | `ghcr.io/paperless-ngx/paperless-ngx:3.2.1` | Web UI, API, consumer, OCR worker (one container) | `./config/paperless/data` (index, classifier; SSD) |
| `paperless-redis` | `redis:7.4-alpine` | Task queue | none (persistence off) |
| — shared `postgres` | stack Postgres | Role + database `paperless` | `postgres_data` volume |

Files on the data HDD under `${PAPERLESS_ROOT}` (`/media/data/paperless`):

| Folder | Purpose |
| --- | --- |
| `media/` | The archive: originals + OCR'd PDF/A copies, named `YEAR/Correspondent/Title.pdf` |
| `consume/` | **Drop folder.** Anything put here is imported, then removed from here |
| `export/` | Target of `document_exporter` (full backup with metadata) |

The database is created once by hand (the shared Postgres has no init scripts for it):

```bash
C=$(docker ps --filter label=com.docker.compose.service=postgres --format '{{.Names}}')
docker exec "$C" psql -U postgres -c "CREATE ROLE paperless LOGIN PASSWORD '<PAPERLESS_DB_PASSWORD>';" \
                                   -c "CREATE DATABASE paperless OWNER paperless;"
```

Deliberately **not** included: Tika + Gotenberg (Office-file conversion, ~500 MB RAM).
PDFs and images import fine; `.docx`/`.xlsx` are rejected. Convert to PDF first, or add
the two containers if that becomes common.

## Login

Behind the `authentik@docker` forward-auth middleware like every other web app. Paperless
trusts Authentik's `X-authentik-username` header (`PAPERLESS_ENABLE_HTTP_REMOTE_USER`),
so after the Authentik login you land in Paperless already signed in as `antoine` — no
second password.

Why that is safe: **every** path on `paperless.<domain>` goes through forward-auth, and
Traefik overwrites the `X-authentik-*` headers with Authentik's answer, so a client
cannot forge them. Remote-user is not enabled for the API (`..._REMOTE_USER_API` is off).
**Never add a second router for this host without the middleware** (e.g. to make the
mobile app work) while remote-user is on — that would let anyone set the header.

`PAPERLESS_ADMIN_PASSWORD` in `.env` is a break-glass local password for the same user,
for use from the LAN if Authentik is down (`http://<server>:8000` is not published, so
via `docker exec` or a temporary port mapping).

Mobile: the Paperless Mobile app cannot pass Authentik forward-auth (same problem as
Immich/Plex). Scan with the phone's camera/scanner app and drop the PDF into the Samba
share instead (below).

## Adding documents

- **Drop folder over SMB:** `\\10.13.89.90\data\paperless\consume` (or
  `smb://10.13.89.90/data/paperless/consume` from the phone, over WireGuard). Files are
  picked up within seconds, OCR'd, and removed from the folder.
  **Subfolders become tags:** `consume/tax/x.pdf` is imported with the tag `tax`.
- **Web upload:** drag files onto the dashboard.
- **Email (later):** Paperless can poll an IMAP mailbox with rules (e.g. "PDF attachments
  from the bank → correspondent BNP, type Statement"). Mail → Mail accounts / Mail rules.

Duplicates (same checksum) are rejected, so re-dropping a folder is safe.

**Gotcha — moving whole folders in:** the consumer watches for new *files* (inotify).
`mv`-ing a directory tree into `consume/` in one go produces a single event for the
directory and nothing gets picked up. Either copy files in (SMB copies are fine), or
after a bulk `mv` run `docker compose restart paperless`: on start the consumer scans
everything already in `consume/`. Import speed on this box is ~15 s per document
including OCR, one at a time.

## How documents are organised

Folders don't work for admin papers (one lease is housing, a country, a landlord and a
year at once), so Paperless files each document once under several labels:

| Label | Examples |
| --- | --- |
| Document type | ID / residence card, certificate, contract, payslip, bank statement, tax, insurance, application form, receipt, booking |
| Correspondent | the bank, the pension/savings provider, the insurer, the city office, the consulate, an employer, a law firm |
| Tags | country (`JP`, `FR`, `SG`, `KH`, `HK`) and topic (`residency`, `marriage`, `housing`, `health`, `work`, `travel`, `tax`) |
| Created date | read from the document; drives the `YEAR/` folder on disk |

Workflow: label the first few documents from each sender by hand; Paperless's matching
("Auto") learns and files the rest. Saved views ("everything tagged `residency`",
"all payslips") replace folder browsing.

## Importing from Google Drive and Gmail

Both connections are **read-only** and live only on the server:

- **Drive:** rclone remote `gdrive:` (`~/bin/rclone`, config `~/.config/rclone/rclone.conf`,
  OAuth scope `drive.readonly`). It uses rclone's shared Google client ID, which Google
  is retiring during 2026 — fine for a one-off import; create an own client ID for any
  ongoing sync (https://rclone.org/drive/#making-your-own-client-id).
- **Gmail:** IMAP with an app password in `~/.config/personal-docs/gmail.env` (chmod 600).
  Mailbox opened with EXAMINE (read-only); scans read headers and attachment names only.

Import pattern: copy the source into a staging folder, **remove what is not a document**
(photos, office files Paperless can't read, secrets such as recovery codes or password
files — those belong in a password manager), then move the staging tree into
`consume/` so folder names become first tags. Inventories live in `~/personal-docs/` on
the server (not in git).

**rclone filter gotcha:** don't mix `--include` and `--exclude` — once an include rule
is present the excludes are effectively ignored (that is how a Drive photo folder
slipped into the first import). Use ordered `--filter` rules instead:

```bash
~/bin/rclone copy gdrive: /media/data/paperless/staging \
  --filter "- other/Photos/**" --filter "- *.txt" \
  --filter "+ *.{pdf,PDF,jpg,JPG,jpeg,png}" --filter "- *"
```

First import (2026-09-25): 187 documents from Drive and the old server admin folder,
7 cross-source duplicates rejected automatically. Gmail backlog not imported yet.

## Resources

One container runs web, consumer and OCR, tuned for the 8 GB box
(`PAPERLESS_TASK_WORKERS=1`, `THREADS_PER_WORKER=1`, `WEBSERVER_WORKERS=1`), limit 1536M.
Idle it is small; OCR of a scanned multi-page PDF is the peak. Bulk imports are queued
and processed one at a time, so a large drop just takes longer rather than swapping the
box. Japanese OCR (`jpn`, `jpn-vert`) is installed at container start
(`PAPERLESS_OCR_LANGUAGES`), which needs internet on first boot.

## Backups

- **Database:** the `paperless` DB is in the shared Postgres, so
  `scripts/backup-postgres.sh` (which discovers databases) already dumps it.
- **Files + metadata, portable:**
  `docker exec paperless document_exporter ../export --delete` writes every original,
  its OCR'd copy and a `manifest.json` with all tags/correspondents/types into
  `${PAPERLESS_ROOT}/export`. That folder alone is enough to rebuild with
  `document_importer`, so it is **the** thing to send off-site (Duplicati/restic → B2).
- Off-site is **not set up yet** (decision pending, 2026-09-25).

## Upgrading

Pinned tag. Read https://github.com/paperless-ngx/paperless-ngx/releases for every
version between the pin and the target, bump the tag, `./deploy.sh`; migrations run on
start (`docker compose logs -f paperless`).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Authentik login loops back to Paperless login | Check the header name: `PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME=HTTP_X_AUTHENTIK_USERNAME`, and that the Authentik user is literally `antoine`. |
| File in `consume/` never disappears | `docker compose logs paperless` — usually an unsupported type (Office file without Tika) or a password-protected PDF. |
| Japanese text not searchable | First boot needs internet to install `jpn`; check the start of the logs, then *Reprocess* the document. |
| Homepage card "API Error" | `PAPERLESS_API_TOKEN` not set: `docker exec paperless python3 manage.py drf_create_token antoine`, put it in `.env`, `docker compose up -d homepage`. |
