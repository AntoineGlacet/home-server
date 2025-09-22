# 🛰️ Home Server on Docker

> Infrastructure-as-code for my Raspberry Pi 4 home lab. Every service runs in Docker, networks are segmented, and a single `.env` file keeps secrets out of version control.

## Stack Landscape

| Stack | Network | Why it exists | Key services |
| --- | --- | --- | --- |
| `HA` | `host` & `zigbeeHA` (10.13.90.0/24) | Smart-home automations via Home Assistant with Zigbee over MQTT. | `home-assistant`, `mqtt`, `zigbee2mqtt` |
| `media` | `media` (10.13.92.0/24) | Media acquisition, library curation, and streaming with a NordVPN egress. | `nordlynx`, `transmission`, `prowlarr`, `sonarr`, `radarr`, `plex`, `overseerr`, `readarr`, `syncthing`, `calibre` |
| `monitoring` | `monitoring_default` (10.13.93.0/24) | Platform observability and alerting. | `uptime-kuma`, `prometheus`, `grafana`, `cadvisor`, `node_exporter` |
| `tools` | `tools` (10.13.91.0/24) | Edge services, SSO, backups, DNS, and portal. | `swag`, `authelia`, `homepage`, `adguard`, `portainer`, `duplicati`, `ddclient`, `samba`, `autoheal`, `fail2ban` |

## Repo Layout

```
home-server
├── .env.example          # template for secrets & tuning (copy to .env locally)
├── README.md             # you are here
├── LICENSE
├── start-all.sh          # spin up every stack
├── stop-all.sh           # stop every stack
├── update-all.sh         # pull + redeploy + prune
├── pull-all.sh           # pull latest images only
├── weekly-update.sh      # cron-friendly update orchestrator
├── HA/
│   ├── docker-compose.yml
│   └── config/           # Home Assistant, Mosquitto, Zigbee2MQTT state
├── media/
│   ├── docker-compose.yml
│   └── config/           # Plex, Overseerr, *arrs, Syncthing, Calibre, etc.
├── monitoring/
│   ├── docker-compose.yml
│   └── config/           # Prometheus rules, Grafana data, Kuma state
└── tools/
    ├── docker-compose.yml
    └── config/           # AdGuard, Authelia, SWAG, Portainer, backups
```

> Actual secrets live in `.env` **outside** of Git. Keep your own copy synced with the hardware and never commit it.

## Operating the Lab

| Action | Command | Notes |
| --- | --- | --- |
| Boot everything | `./start-all.sh` | Reads stack order and references `.env` for shared vars. |
| Stop everything | `./stop-all.sh` | Brings stacks down in reverse order. |
| Refresh images | `./update-all.sh` | Pulls images, redeploys, and prunes dangling layers. |
| Pull only | `./pull-all.sh` | Useful before scheduled maintenance windows. |
| Weekly automation | `./weekly-update.sh` | Wrapper for unattended updates + notifications. |

### Environment & Secrets

- Copy `.env.example` to `.env` on the host and populate credentials (`PUID`, `PGID`, `TZ`, VPN keys, Cloudflare token, etc.).
- All compose files expect the `.env` file to sit next to the scripts, so run commands from the repo root.
- Per-service configuration lives under each stack’s `config/` directory and is bind-mounted back into containers.

### Networking Notes

- `swag` (reverse proxy) owns `10.13.88.88` and handles TLS via Cloudflare DNS-01, then forwards through `authelia` for SSO.
- NordVPN egress is enforced by `network_mode: service:nordlynx` for Transmission and Prowlarr to keep metadata private.
- Host-mode workloads (`home-assistant`, `plex`, `fail2ban`, `node_exporter`) need raw LAN access for device discovery and firewalling.
- Internal DNS (`adguard`) and DHCP let the Pi act as the network edge, while `ddclient` updates the public hostname.

## Network Architecture

```mermaid
flowchart LR
    classDef host fill:#fde2e4,stroke:#b56576,color:#111;
    classDef vpn fill:#ffe066,stroke:#f3722c,color:#111;
    classDef monitor fill:#dbe7ff,stroke:#3a0ca3,color:#111;
    classDef edge fill:#d8f3dc,stroke:#2d6a4f,color:#111;

    wan((Internet))
    lan((Home LAN clients))

    subgraph HostLAN["Host LAN / Docker Engine"]
        docker[Docker Engine]
        homeassistant["home-assistant"]
        plex["plex"]
        fail2ban["fail2ban"]
        nodeexporter["node_exporter"]
        glances["glances"]
    end
    class homeassistant,plex,fail2ban,nodeexporter,glances host;

    subgraph Zigbee["zigbeeHA<br/>10.13.90.0/24"]
        mqtt["mqtt"]
        zigbee2mqtt["zigbee2mqtt"]
    end

    subgraph Media["media<br/>10.13.92.0/24"]
        nordlynx["nordlynx<br/>(VPN tunnel)"]
        transmission["transmission"]
        prowlarr["prowlarr"]
        sonarr["sonarr"]
        radarr["radarr"]
        overseerr["overseerr"]
        bazarr["bazarr"]
        readarr["readarr"]
        syncthing["syncthing"]
        calibre["calibre-web-automated"]
    end
    class nordlynx vpn;

    subgraph Tools["tools<br/>10.13.91.0/24"]
        homepage["homepage"]
        adguard["adguard"]
        portainer["portainer"]
        duplicati["duplicati"]
        ddclient["ddclient"]
        samba["samba"]
        autoheal["autoheal"]
    end
    class homepage,adguard,portainer,duplicati,ddclient,samba,autoheal edge;

    subgraph SwagNet["swag<br/>10.13.88.0/24"]
        swag["swag<br/>(10.13.88.88)"]
        authelia["authelia"]
    end

    subgraph Monitoring["monitoring_default<br/>10.13.93.0/24"]
        uptime["uptime-kuma"]
        prometheus["prometheus"]
        grafana["grafana"]
        cadvisor["cadvisor"]
    end
    class uptime,prometheus,grafana,cadvisor monitor;

    wan --> swag
    lan --> adguard
    swag --> authelia
    authelia --> homepage
    authelia --> portainer
    authelia --> grafana

    homepage --> lan
    portainer --> docker
    autoheal --> docker
    duplicati --> backup[(Backup target)]
    ddclient --> dns[(Cloudflare DNS)]
    samba --> lan

    homeassistant -- automations --> mqtt
    zigbee2mqtt -- publishes --> mqtt
    zigbee2mqtt -. "USB Zigbee stick" .- homeassistant

    docker --> homeassistant
    docker --> plex
    docker --> fail2ban

    prometheus --> nodeexporter
    prometheus --> cadvisor
    grafana --> prometheus
    uptime -. monitors .- swag
    uptime -. monitors .- plex

    nordlynx --> vpnexit((NordVPN POP))
    transmission -. shares namespace .- nordlynx
    prowlarr -. shares namespace .- nordlynx
    sonarr --> transmission
    radarr --> transmission
    overseerr --> sonarr
    overseerr --> radarr
    bazarr --> sonarr
    readarr --> transmission

    plex --> lan
    syncthing --> lan
```

### Monitoring & Self-Healing

- Prometheus scrapes `node_exporter` (host metrics) and `cadvisor` (container metrics); Grafana dashboards visualize both.
- `uptime-kuma` keeps an eye on web UIs and external endpoints.
- `autoheal` watches healthchecks and restarts unhealthy containers automatically.

### Storage & Backups

- Media libraries mount from host paths defined in `.env` (`${MEDIA}`, `${MOVIES}`, `${TV}`, `${DOWNLOADS}`, etc.).
- `duplicati` targets `${BACKUP}` for encrypted backups; customize retention and destinations in `config/duplicati`.
- Samba exposes `${DATA}` to Windows clients for simple drag-and-drop access.
