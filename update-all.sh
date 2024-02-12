#!/usr/bin/env bash

# list of all folders to consider
# Declare an array of string with type
declare -a StringArray=("tools" "media" "HA" "monitoring")

# Loop over folders and reference the env-file
# Iterate the string array using for loop
for val in "${StringArray[@]}"; do
   docker compose --file "$val"/docker-compose.yml --env-file .env pull
   docker compose --file "$val"/docker-compose.yml --env-file .env up -d
done

# prune
docker system prune -f
