# Home Server on docker

configuration for my home server running on Raspberry Pi 4

# Organization

Everything is organised around 3 stacks:

- HA (home assistant)
To run a smart home and automation. This includes home asssistant mosquitto and zigbee2mqtt

- plex (media server)
To manage video media library (including downloads) and streaming it.
This includes jackett, plex, radarr, sonarr and transmission.

- tools
some supervision and file sharing tools.
This includes heimdall, portainer and samba.

Each stack has its own docker-compose.yml file with the configuration and a .env file with secrets (not uploaded to github).
Each stack has a folder 'config' where each container store its persistent config infos.

on top of that are simple scripts to stop and start all stacks with one command.

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
|       ├── mosquitto                 <- message broker
|       └── zigbee2mqtt               <- for zigbee devices
|
├── plex
|   ├── docker-compose.yml
│   └── config            
│       ├── jackett                   <- torrent tracker aggregator
|       ├── plex                      <- media server
|       ├── radarr                    <- movie library manager
|       ├── sonarr                    <- TV library manager
|       └── transmission              <- torrent downloader (+VPN client)
├── tools
|   ├── docker-compose.yml
│   └── config            
│       ├── heimdall                  <- web UI portal
|       ├── portainer                 <- web UI for container management
|       └── samba                     <- file sharing server
```