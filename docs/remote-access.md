---
title: "Remote Access (WireGuard + Game Streaming)"
weight: 6
description: "Secure remote access to the home LAN via WireGuard (wg-easy), with AdGuard DNS and Sunshine/Moonlight game streaming to the Windows PC"
---

Secure access to the home LAN from anywhere, plus low-latency desktop/game streaming to
the Windows gaming PC — all over a single self-hosted WireGuard tunnel. No third-party
relay, control plane, or SaaS.

## Table of Contents

- [Architecture](#architecture)
- [How it works](#how-it-works)
- [One-time prerequisites](#one-time-prerequisites-you)
- [Adding a device (admin)](#adding-a-device-admin)
- [Game streaming: Sunshine + Moonlight](#game-streaming-sunshine--moonlight)
- [Family quick-start](#family-quick-start)
- [Troubleshooting](#troubleshooting)

## Architecture

| Layer | Component | Role |
| --- | --- | --- |
| **VPN** | `wg-easy` (WireGuard) on the OptiPlex | Encrypted tunnel into the LAN; QR-code device onboarding |
| **DNS** | AdGuard Home (existing) | Ad-blocking + internal name resolution for VPN clients |
| **Game stream** | Sunshine (Windows PC) + Moonlight (clients) | Hardware-encoded desktop/game streaming **over** the VPN |
| **Public web** | Traefik + Authentik (existing) | A few browser apps stay reachable without the VPN |

Only **one** port faces the internet: **UDP 51820** (WireGuard). SSH, NAS/SMB, the wg-easy
admin UI, and Sunshine are **never** exposed publicly — they're reachable only once you're on
the VPN (or on the LAN).

## How it works

- `wg-easy` runs on the OptiPlex (`10.13.89.90`) and is defined in `docker-compose.yml` under
  the **REMOTE ACCESS VPN** section.
- Clients connect to `WG_HOST` (`antoineglacet.com`, kept pointed at the home IP by `ddclient`)
  on UDP 51820.
- The host has `ip_forward=1` and `wg-easy` sets up masquerading, so a connected client can
  reach the **entire `10.13.0.0/16` LAN** — including the Windows gaming PC and AdGuard — even
  though those machines are not WireGuard peers themselves.
- Clients use **AdGuard** (`10.13.89.90`) for DNS by default (full-tunnel), so ad-blocking and
  internal hostnames work everywhere.

Admin UI: **http://10.13.89.90:51821** (on the LAN, or via the VPN). Not on the internet.

## One-time prerequisites (you)

These are on devices/hardware outside the server, so they can't be scripted from the repo:

1. **Router port-forward:** forward **UDP 51820 → 10.13.89.90:51820**. Until this is done, the
   VPN only works from inside the LAN. (Docker publishes the port directly, so UFW on the host
   does not need a rule; if a connection from the internet still fails, confirm the forward.)
2. **Gaming PC static IP:** give the Windows PC a **static DHCP reservation** on the router so
   its LAN IP doesn't change (Moonlight connects to it by IP).

## Adding a device (admin)

1. On the LAN (or already connected to the VPN), open **http://10.13.89.90:51821** and log in
   with the wg-easy admin password.
2. **New → name the client** (e.g. `wife-iphone`, `work-laptop`). wg-easy generates the keys.
3. Install the official **WireGuard** app on the device.
   - Phone: tap the client's **QR code** in the wg-easy UI and scan it in the WireGuard app.
   - Desktop: **download** the `.conf` and import it in the WireGuard app.
4. Toggle the tunnel on. The device can now reach every internal service (SSH, NAS, Home
   Assistant app, web UIs by hostname, etc.).

Per-device routing can be changed in the UI (e.g. switch a roaming phone to split-tunnel so
only home traffic goes through the tunnel). Default is full-tunnel.

## Game streaming: Sunshine + Moonlight

Streaming runs **inside** the VPN — Sunshine's ports stay on the LAN and are never forwarded.

### On the Windows gaming PC (once)

1. Install **Sunshine** (`winget install LizardByte.Sunshine` or the GitHub release). Let it
   install as a service and allow its firewall rules.
2. Open **https://localhost:47990**, create the Sunshine username/password, and confirm the
   desktop appears as an app.
3. Note the PC's static LAN IP (from the reservation above).

### On each client (phone / laptop / desktop)

1. Install **Moonlight** (Android, iOS, Windows, macOS, Linux, Steam Deck).
2. **Connect the WireGuard VPN first.**
3. In Moonlight, **Add Host** by the gaming PC's **LAN IP** (e.g. `10.13.x.y`).
4. Moonlight shows a **PIN** → enter it in Sunshine's web UI (**PIN** page) to pair.
5. Pick the desktop/app and stream. Use a gamepad over Bluetooth/USB as normal.

> For best latency: on a strong connection full-tunnel is fine. If a particular client streams
> poorly, set that client to split-tunnel (still routing `10.13.0.0/16`) in the wg-easy UI.

## Family quick-start

> **To play / access home stuff remotely:** turn on the **VPN** toggle → open **Moonlight** →
> tap the **PC** → play. For websites/apps, just toggle the VPN on.

On iPhone/Android, set the WireGuard tunnel to **On-Demand / Always-on** so it reconnects
automatically and it's effectively one tap.

## Troubleshooting

- **Can't connect from outside but works on LAN** → router port-forward (UDP 51820) missing or
  wrong target IP, or `WG_HOST` not resolving to the home IP (check `ddclient`).
- **Connected but no internet / DNS** → check `WG_DEFAULT_DNS=10.13.89.90` and that AdGuard is
  up; verify the client shows in AdGuard's query log.
- **Can't reach a LAN host** → confirm the client's Allowed IPs include `10.13.0.0/16` (or
  `0.0.0.0/0`); from the server, `docker exec wg-easy ping -c1 <host-ip>`.
- **Moonlight can't find the PC** → ensure the VPN is connected first and you're using the PC's
  LAN IP; confirm Sunshine is running and paired.
- **wg-easy logs:** `docker compose logs -f wg-easy` on the OptiPlex.
