#!/usr/bin/env bash
# Run wire-pod (Vector's self-hosted voice server) in a container on this machine.
#
# Host networking so the robot can reach it directly and wire-pod advertises the
# host's LAN address. Rootful because wire-pod binds ports 80 and 443.
# State (config, certs, API keys entered in the web UI) lives in the
# "wire-pod-data" volume, not in this repo.
#
# Web UI: http://<this-host>:8080
set -euo pipefail

IMAGE="${WIREPOD_IMAGE:-ghcr.io/kercre123/wire-pod:main}"
ENGINE="${CONTAINER_ENGINE:-podman}"

sudo "$ENGINE" pull "$IMAGE"
sudo "$ENGINE" rm -f wire-pod 2>/dev/null || true
sudo "$ENGINE" run -d \
  --name wire-pod \
  --network host \
  --restart unless-stopped \
  -e WIREPOD_DATA_DIR=/data \
  -v wire-pod-data:/data \
  -v wire-pod-images:/images \
  "$IMAGE"

echo "wire-pod started. Web UI: http://$(hostname -I | awk '{print $1}'):8080"
