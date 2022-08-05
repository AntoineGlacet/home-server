#!/usr/bin/env bash

# list of all folders to consider
# Declare an array of string with type
declare -a StringArray=( "tools" "media" "HA"  )
 
# Loop over folders and reference the env-file
# Iterate the string array using for loop
for val in ${StringArray[@]}; do
   docker compose --file $val/docker-compose.yml --env-file .env up -d --remove-orphans
done