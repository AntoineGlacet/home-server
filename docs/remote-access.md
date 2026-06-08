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
- [DNS & the VPN endpoint](#dns--the-vpn-endpoint)
- [Port forwarding](#port-forwarding)
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

The remote-access + streaming path adds exactly **one** inbound port: **UDP 51820** (WireGuard).
SSH, NAS/SMB, the wg-easy admin UI, and Sunshine are **never** exposed publicly — they ride
inside the tunnel. (Separately, the public web stack uses **TCP 443** via Cloudflare — see
[Port forwarding](#port-forwarding).)

## How it works

- `wg-easy` runs on the OptiPlex (`10.13.89.90`) and is defined in `docker-compose.yml` under
  the **REMOTE ACCESS VPN** section.
- Clients connect to `WG_HOST` = **`vpn.antoineglacet.com`** on UDP 51820 — a dedicated
  **DNS-only (grey-cloud)** Cloudflare record kept current by `ddclient`. It must **not** be the
  proxied apex; see [DNS & the VPN endpoint](#dns--the-vpn-endpoint).
- The host has `ip_forward=1` and `wg-easy` sets up masquerading, so a connected client can
  reach the **entire `10.13.0.0/16` LAN** — including the Windows gaming PC and AdGuard — even
  though those machines are not WireGuard peers themselves.
- Clients use **AdGuard** (`10.13.89.90`) for DNS by default (full-tunnel), so ad-blocking and
  internal hostnames work everywhere.

Admin UI: **http://10.13.89.90:51821** (on the LAN, or via the VPN). Not on the internet.

## DNS & the VPN endpoint

WireGuard's handshake is **UDP**. `antoineglacet.com` and its subdomains are **proxied through
Cloudflare** (orange cloud) — Cloudflare relays HTTP/S (80/443) but **silently drops the
WireGuard UDP**, so pointing clients at the proxied name means the handshake never reaches home
(the peer shows up with zero transfer). That was the original "connects but no internet" bug.

The fix, and the standing rule:

- **`vpn.antoineglacet.com`** is a separate **A record set to DNS-only (grey cloud)** so it
  resolves straight to the home public IP. `ddclient` keeps it updated
  (`config/ddclient/ddclient.conf`) as the dynamic IP changes. `WG_HOST` points here.
- **Split-horizon (already in place):** AdGuard has a `*.antoineglacet.com → 10.13.89.90`
  rewrite, so on the LAN (and once on the VPN) the web hostnames resolve to the local Traefik
  IP — no NAT hairpin. Cellular clients (not yet on the VPN) get the public IP from Cloudflare.
  Both paths are correct; nothing to change.
- If you ever recreate the record, keep it **grey-cloud**. To verify it's not proxied:
  `curl -s 'https://1.1.1.1/dns-query?name=vpn.antoineglacet.com&type=A' -H 'accept: application/dns-json'`
  should return the home IP, not a `104.x`/`172.67.x` Cloudflare address.

## Port forwarding

Router (WAN → `10.13.89.90`) port-forward rules needed:

| Port | Needed? | Why |
| --- | --- | --- |
| **UDP 51820** | **Yes** | WireGuard data plane — the only inbound port the VPN/streaming path needs |
| **TCP 443** | **Yes** | Public web stack (Cloudflare proxy → Traefik origin over HTTPS) |
| **TCP 80** | **No** | TLS certs use the Cloudflare **DNS-01** challenge (not HTTP-01), and Cloudflare does the http→https redirect itself. Forwarding 80 from the WAN is unnecessary; you can drop it to shrink attack surface. (Keep Traefik's local `:80` publish so LAN http→https redirects still work.) |

> Confirm Cloudflare's SSL/TLS mode is **Full (strict)** — that's what makes Cloudflare connect
> to the origin on 443. The router must **never** forward 51821 (the wg-easy admin UI).

## One-time prerequisites (you)

These are on devices/hardware outside the server, so they can't be scripted from the repo:

1. **Router port-forward:** forward **UDP 51820 → 10.13.89.90:51820** (see
   [Port forwarding](#port-forwarding) for the full list). Until this is done, the VPN only
   works from inside the LAN. (Docker publishes the port directly, so UFW on the host does not
   need a rule; if a connection from the internet still fails, confirm the forward.)
2. **Cloudflare DNS record:** `vpn.antoineglacet.com` must exist as a **DNS-only (grey-cloud)**
   A record (created once; `ddclient` then keeps its IP current). See
   [DNS & the VPN endpoint](#dns--the-vpn-endpoint).
3. **Gaming PC static IP:** give the Windows PC a **static DHCP reservation** on the router so
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

## Waking the gaming PC (Wake-on-LAN)

Moonlight's **Wake** button works over WireGuard thanks to a static-ARP helper. A WoL
magic packet only wakes a PC if it physically reaches its NIC; from the VPN that fails by
default because the tunnel ends inside the `wg-easy` container (off the LAN's broadcast
domain) and a powered-off PC has no ARP entry. The `wol-arp` service (in
`docker-compose.yml`, host-net + `NET_ADMIN`) keeps a **permanent static ARP entry** for
the PC on the host's `enp1s0`:

```
ip neigh replace 10.13.89.126 lladdr 6c:02:e0:40:24:51 nud permanent dev enp1s0
```

So Moonlight's unicast magic packet (routed over the tunnel → wg-easy → host) is forwarded
onto the LAN to the PC's MAC even while it sleeps. If the PC's IP or MAC changes, update
the `wol-arp` command and keep a static DHCP reservation.

**PC-side prerequisites (one-time, on the Windows gaming PC):**
- BIOS/UEFI: enable **Wake-on-LAN** / "Power On by PCIe/PCI".
- Windows: Device Manager → your NIC → **Power Management**: "Allow this device to wake the
  computer"; **Advanced** → "Wake on Magic Packet" = Enabled.
- **Disable Fast Startup** (Control Panel → Power Options → "Choose what the power buttons
  do" → uncheck *Turn on fast startup*). Fast Startup makes shutdown a hybrid state where
  WoL usually fails; sleep/hibernate are fine.
- Give the PC a **static DHCP reservation** so its IP↔MAC stay put.

Then from the phone (on the VPN): Moonlight → the host → **Wake**.

## Family quick-start

> **To play / access home stuff remotely:** turn on the **VPN** toggle → open **Moonlight** →
> tap the **PC** → play. For websites/apps, just toggle the VPN on.

On iPhone/Android, set the WireGuard tunnel to **On-Demand / Always-on** so it reconnects
automatically and it's effectively one tap.

## Troubleshooting

- **Can't connect from outside but works on LAN** → router port-forward (UDP 51820) missing or
  wrong target IP; or `WG_HOST` points at a **Cloudflare-proxied** name (must be the grey-cloud
  `vpn.antoineglacet.com`); or that record isn't resolving to the home IP (check `ddclient`).
  Tell-tale sign: on the server, `docker exec wg-easy wg show` lists the peer with **no
  handshake / 0 B transfer** — the packets aren't reaching home.
- **Endpoint on the client shows the wrong host** → after changing `WG_HOST`, re-scan the QR (or
  edit the client's `Endpoint` to `vpn.antoineglacet.com:51820`); keys are unchanged.
- **Connected but no internet / DNS** → check `WG_DEFAULT_DNS=10.13.89.90` and that AdGuard is
  up; verify the client shows in AdGuard's query log.
- **Can't reach a LAN host** → confirm the client's Allowed IPs include `10.13.0.0/16` (or
  `0.0.0.0/0`); from the server, `docker exec wg-easy ping -c1 <host-ip>`.
- **Moonlight can't find the PC** → ensure the VPN is connected first and you're using the PC's
  LAN IP; confirm Sunshine is running and paired.
- **wg-easy logs:** `docker compose logs -f wg-easy` on the OptiPlex.
