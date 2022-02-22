#!/usr/bin/env bash

cd tools
docker-compose up -d
cd ..

cd HA
docker-compose up -d
cd ..

cd plex
docker-compose up -d
cd ..