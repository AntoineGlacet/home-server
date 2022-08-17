#!/usr/bin/env bash
# file used as root cron for weekly update of whole server

# home server directory
HOMESERVER="/home/ubuntu/home-server/"

# to record cmd output in log and to ouput for emailing with cron
log_cmd() {
   now=$(date)
   "$@" 2>&1 | awk -v now="$now" '{ printf("[%s]\t%s\n", now, $0) }' | tee -a /var/tmp/cron.logtest
}

# update and upgrade all packages
log_cmd sudo apt update -q -y && log_cmd sudo apt upgrade -q -y

# pull and restart all stacks
declare -a StringArray=("tools" "media" "HA")
for val in "${StringArray[@]}"; do
   log_cmd docker compose --file "$HOMESERVER""$val"/docker-compose.yml --env-file "$HOMESERVER".env pull -q
   log_cmd docker compose --file "$HOMESERVER""$val"/docker-compose.yml --env-file "$HOMESERVER".env up -d
done

# # prune
docker system prune -f

# restart for good measure
# if [ -f /var/run/reboot-required ]; then
#    sudo reboot -h now
# fi
