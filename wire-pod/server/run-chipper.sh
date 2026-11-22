#!/usr/bin/env bash
# Starts wire-pod (chipper) with /data/chipper as its working directory, in place of the image's
# start.sh. Runs after the image's entrypoint, which has already copied certs/, vosk/, stt/ etc.
# into /data.
#
# Why: the image keeps its config files (apiConfig.json, botConfig.json, ...) in the image and
# symlinks them into /data, but wire-pod saves them with write-temp-then-rename, which replaces
# the symlink with a file inside the container. Quadlet recreates the container on every start,
# so settings and robot registrations were lost on each restart. Every path wire-pod uses is
# relative to its working directory (./apiConfig.json, ../certs, ../vosk/models), and /data
# mirrors the image layout, so running from /data/chipper makes it write straight to disk.
set -euo pipefail

APP=/opt/wire-pod
cd /data/chipper

# Read-only parts of the image, linked fresh on each start so image updates apply.
for f in chipper webroot intent-data epod weather-map.json stttest.pcm; do
  ln -sfn "$APP/chipper/$f" "$f"
done
mkdir -p /data/vector-cloud
ln -sfn "$APP/vector-cloud/pod-bot-install.sh" /data/vector-cloud/pod-bot-install.sh

# shellcheck disable=SC1091
source ./source.sh
exec ./chipper
