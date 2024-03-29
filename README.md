# Home Server on docker

configuration for my home server running on Raspberry Pi 4

# Organization

Everything is organised around 3 stacks:

- **HA (home assistant)**
To run a smart home and automation. This includes home asssistant mosquitto and zigbee2mqtt

- **media (media server)**
To manage video media library (including downloads) and streaming it.
Routing traffic of download client (transmission and prowlarr) through VPN (Nordlynx)

- **Tools**
Supervision tools, fileshare, reverse proxy, landing page, etc...

Each stack has its own docker-compose.yml file with the configuration and a folder 'config' where each container store its persistent config infos.

on the root folder there is a .env file with secrets (not uploaded to github) and some simple scripts to start, stop and update all stacks with one command.

# Tree structure
```
home-server
├── .env                              <- all env variables (not uploaded to github)
├── LICENSE                                   └──> passwords and other secrets
├── README.md
├── start-all.sh                      <- script to start all docker-compose
├── stop-all.sh                       <- script to stop all docker-compose
├── update-all.sh                     <- script to update all docker-compose|
├── HA
|   ├── docker-compose.yml
│   └── config            
│       ├── homeassistant             <- manages all smart home
|       |   ├── automations.yaml
|       |   ├── configuraton.yaml
|       |   └── scripts.yaml
|       ├── node-red                  <- automation progamming (not used currently)
|       ├── mosquitto                 <- message broker
|       └── zigbee2mqtt               <- for zigbee devices
|
├── media
|   ├── docker-compose.yml
│   └── config            
│       ├── bazarr                    <- subtitles manager
│       ├── calibre                   <- ebook server
│       ├── overseerr                 <- media discovery and request
|       ├── plex                      <- media server (video)
|       ├── prowlarr                  <- indexer aggregator
|       ├── radarr                    <- movie library manager
|       ├── sonarr                    <- TV library manager
|       └── transmission              <- torrent client
├── tools
|   ├── docker-compose.yml
│   └── config            
│       ├── adguard                   <- network-wide ad blocking
│       ├── authelia                  <- authentification
│       ├── code-server               <- VScode
│       ├── duplicati                 <- regular backups
│       ├── glances                   <- process monitoring
│       ├── heimdall                  <- web UI portal
|       ├── portainer                 <- web UI for container management
|       └── swag                      <- reverse proxy and ssl
|       └── wireguard                 <- VPN server
```