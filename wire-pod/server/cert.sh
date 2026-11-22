#!/usr/bin/env bash
# cert.sh: give wire-pod a Tailscale (Let's Encrypt) certificate for this server's MagicDNS name,
# so robots on the tailnet can verify it. Run weekly by wire-pod-cert.timer (`just server-install`);
# restarts wire-pod only when the certificate changed.
#
# Does nothing until the robot uses the tailnet name. `just wirepod-ts-cert` marks that by setting
# wire-pod's own LAN certificate aside as cert.*.selfsigned-lan, then runs this.
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "run with sudo" >&2; exit 1; fi
CERTS=$(cd "$(dirname "$0")" && pwd)/data/certs
NAME=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')

if [[ ! -f $CERTS/cert.crt.selfsigned-lan ]]; then
  echo "wire-pod still uses its LAN certificate; nothing to do"
  exit 0
fi

before=$(sha256sum "$CERTS/cert.crt" 2>/dev/null | cut -d' ' -f1 || true)
tailscale cert --cert-file "$CERTS/cert.crt" --key-file "$CERTS/cert.key" "$NAME"
after=$(sha256sum "$CERTS/cert.crt" | cut -d' ' -f1)

if [[ $before != "$after" ]]; then
  echo "certificate renewed; restarting wire-pod"
  systemctl restart wire-pod
else
  echo "certificate unchanged"
fi
