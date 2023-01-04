#!/usr/bin/env bash

# script to manually link downloaded episodes to media directory

source_parent_dir="/media/data/downloads/complete/[AnimeRG] One Piece (Episodes 001-837) Seasons 01-19 [1080p] [Dual-Audio] [Multi-Sub] [HEVC] [x265] [Ultimate Batch 2018] [pseudo]/"
target_dir="/media/data/media/tv/One Piece/"

for episode in "$source_parent_dir"*/"[AnimeRG] One Piece - "*".mkv"; do
    ln "$episode" "$target_dir"
done
