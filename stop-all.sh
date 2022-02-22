#!/usr/bin/env bash

cd tools
docker-compose down
cd ..

cd HA
docker-compose down
cd ..

cd plex
docker-compose down
cd ..