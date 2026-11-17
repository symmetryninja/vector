# Vector (WireOS) helpers. Run `just` to list recipes.
#
# Private values never go in this file. Override the defaults below with
# environment variables, or put them in local/.env (gitignored), e.g.:
#   VECTOR_HOST=Vector.local
#   VECTOR_KEY=/home/me/.ssh/vector_private_key
# See env.example for every setting.

set dotenv-path := "local/.env"
set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]

vector_host := env("VECTOR_HOST", "Vector.local")
vector_key := env("VECTOR_KEY", home_directory() / ".ssh/vector_private_key")
engine := env("CONTAINER_ENGINE", "podman")
wirepod_web_port := env("WIREPOD_WEB_PORT", "8080")
wirepod_ui := env("WIREPOD_UI", "http://localhost:" + wirepod_web_port)
llm_model := env("LLM_MODEL", "qwen2.5:7b")
llm_endpoint := env("LLM_ENDPOINT", "http://localhost:11434/v1")
ts_version := env("TS_VERSION", "1.104.5")

# Older WireOS builds only offer ssh-rsa host keys.
ssh_opts := "-i " + vector_key + " -o BatchMode=yes -o ConnectTimeout=8 -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa"
ssh := "ssh " + ssh_opts + " root@" + vector_host

# List recipes
default:
    @just --list --unsorted

# ---------------------------------------------------------------------------
# Everything at once

# Start Ollama and wire-pod, then check wire-pod's ports
[group('stack')]
up: ollama-start wirepod-start wirepod-status

# Stop wire-pod and Ollama
[group('stack')]
down: wirepod-stop ollama-stop

# ---------------------------------------------------------------------------
# Robot

# Find Vector on the network via mDNS
[group('robot')]
find:
    avahi-browse -rt _ankivector._tcp | grep -E 'hostname|address' | sort -u

# Open a shell on Vector, or run a command: just ssh 'uptime'
[group('robot')]
ssh *cmd:
    {{ssh}} {{ if cmd == "" { "" } else { quote(cmd) } }}

# Services, connections, memory and load on Vector
[group('robot')]
status:
    {{ssh}} 'uptime; echo; for s in vic-cloud vic-engine vic-anim vic-robot vic-switchboard wired; do printf "%-16s %s\n" $s "$(systemctl is-active $s)"; done; echo; free -m | sed -n 1,2p; echo; echo "connections (excluding SSH):"; ss -tnp state established 2>/dev/null | grep -v ":22 " | tail -n +2'

# Everything Vector is connected to, for the "what leaves the house" check
[group('robot')]
connections:
    {{ssh}} 'ss -tunp 2>/dev/null | grep -v ":22 "'

# Show Vector's log, optionally filtered: just logs vic-cloud
[group('robot')]
logs pattern="." lines="200":
    {{ssh}} 'tail -{{lines}} /var/log/messages | grep -aiE "{{pattern}}"'

# Restart Vector's robot software as a group (restarting vic-cloud alone breaks its sockets)
[group('robot')]
restart-robot:
    {{ssh}} 'systemctl restart anki-robot.target'

# Reboot Vector
[group('robot')]
reboot:
    -{{ssh}} 'systemctl reboot'

# Show Vector's IP, firmware and WireOS settings page
[group('robot')]
info:
    {{ssh}} 'echo "ip:       $(ip -4 -o addr show wlan0 | awk "{print \$4}")"; echo "firmware: $(cat /anki/etc/version)"; echo "kernel:   $(uname -r)"'
    @echo "settings: http://{{vector_host}}:8080"

# ---------------------------------------------------------------------------
# Privacy and updates

# Stop and mask the cloud voice service so no audio leaves the robot
[group('privacy')]
voice-cloud-off:
    {{ssh}} 'systemctl stop vic-cloud; mount -o rw,remount / && systemctl mask vic-cloud; mount -o ro,remount /; systemctl is-enabled vic-cloud || true'

# Unmask and start the cloud voice service (check server_config.json first!)
[group('privacy')]
voice-cloud-on:
    {{ssh}} 'cat /data/data/server_config.json 2>/dev/null || echo "no /data/data/server_config.json: would use the built-in community server"; echo'
    {{ssh}} 'mount -o rw,remount / && systemctl unmask vic-cloud; mount -o ro,remount /; systemctl restart anki-robot.target; sleep 5; systemctl is-active vic-cloud'

# Block the WireOS community voice server on the robot (runtime only; a reboot undoes it)
[group('privacy')]
block-community-server:
    {{ssh}} 'for ip in $(nslookup vicapi.pvic.xyz 2>/dev/null | awk "/^Name:/ {n=1} n && /^Address/ {print \$3}" | grep -E "^[0-9.]+$"); do iptables -C OUTPUT -d $ip -j REJECT 2>/dev/null || iptables -I OUTPUT -d $ip -j REJECT; done; iptables -L OUTPUT -v -n | grep REJECT || echo "no addresses resolved"'

# Is auto-update allowed?
[group('privacy')]
autoupdate-status:
    #!/usr/bin/env bash
    if ! r="$(curl -sf -m 8 http://{{vector_host}}:8080/api/mods/AutoUpdate/isInhibitedByUser)"; then
      echo "can't reach Vector's settings page at {{vector_host}}:8080"; exit 1
    fi
    case "$r" in *true*) echo "auto-update: off";; *) echo "auto-update: ON";; esac

# Turn auto-update off (stored on /data, survives reboots)
[group('privacy')]
autoupdate-off:
    curl -s http://{{vector_host}}:8080/api/mods/AutoUpdate/setInhibited; echo
    @just autoupdate-status

# Turn auto-update back on
[group('privacy')]
autoupdate-on:
    curl -s http://{{vector_host}}:8080/api/mods/AutoUpdate/setAllowed; echo
    @just autoupdate-status

# ---------------------------------------------------------------------------
# Wi-Fi

# List Wi-Fi networks Vector can see, and the ones he has saved
[group('wifi')]
wifi-list:
    {{ssh}} 'connmanctl services; echo; echo "saved:"; ls /data/lib/connman | grep ^wifi_ || true'

# Add a Wi-Fi network interactively (agent on, scan wifi, services, connect <id>)
[group('wifi')]
wifi-add:
    @echo "In connmanctl run: agent on / scan wifi / services / connect <wifi_...id> / quit"
    ssh -t {{ssh_opts}} root@{{vector_host}} connmanctl

# ---------------------------------------------------------------------------
# Flashing

# Install a full OTA over SSH, no website needed: just flash-url http://ota.pvic.xyz/vic/latest/dev.ota
[group('flash')]
flash-url url:
    {{ssh}} 'update-os {{url}}'

# Serve a local .ota from this machine and install it on Vector
[group('flash')]
flash-file file port="8000":
    #!/usr/bin/env bash
    set -euo pipefail
    ota="$(realpath "{{file}}")"
    vec_ip="$(getent hosts {{vector_host}} | awk '{print $1; exit}')"
    my_ip="$(ip route get "$vec_ip" | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
    echo "sha256: $(sha256sum "$ota" | cut -d' ' -f1)"
    python3 -m http.server {{port}} --bind "$my_ip" --directory "$(dirname "$ota")" &
    server=$!
    trap 'kill $server' EXIT
    sleep 1
    {{ssh}} "update-os http://$my_ip:{{port}}/$(basename "$ota")"

# ---------------------------------------------------------------------------
# wire-pod (voice server, runs on this machine)

# Create (or recreate) the wire-pod container from the latest image
[group('wire-pod')]
wirepod-run:
    ./wire-pod/run.sh

# Start the existing wire-pod container
[group('wire-pod')]
wirepod-start:
    sudo {{engine}} start wire-pod
    @sleep 10

# Stop wire-pod
[group('wire-pod')]
wirepod-stop:
    -sudo {{engine}} stop -t 10 wire-pod

# Restart wire-pod
[group('wire-pod')]
wirepod-restart:
    sudo {{engine}} restart -t 5 wire-pod
    @sleep 10
    @just wirepod-status

# Follow wire-pod's log
[group('wire-pod')]
wirepod-logs:
    sudo {{engine}} logs -f --tail 50 wire-pod

# Check wire-pod is running and listening (443 = voice, web UI port)
[group('wire-pod')]
wirepod-status:
    #!/usr/bin/env bash
    sudo {{engine}} ps -a --filter name=wire-pod --format '{{{{.Names}}: {{{{.Status}}'
    for p in 443 {{wirepod_web_port}}; do
      owner="$(sudo ss -tlnpH "sport = :$p" | grep -o '(("[^"]*"' | head -1 | tr -d '(\"')"
      case "$owner" in
        chipper) echo "port $p: wire-pod";;
        "")      echo "port $p: not listening";;
        *)       echo "port $p: taken by $owner (not wire-pod)";;
      esac
    done
    sudo ss -tlnpH "sport = :443" | grep -q chipper || echo "voice port down: start wire-pod, or 'just wirepod-restart' if it's running"

# First-time setup of a fresh wire-pod: English Vosk, IP mode on port 443 (works around the image's first-start bugs)
[group('wire-pod')]
wirepod-init language="en-US":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "restarting once so wire-pod reads its speech settings..."
    sudo {{engine}} restart -t 5 wire-pod >/dev/null; sleep 12
    curl -s -X POST -H 'Content-Type: application/json' -d '{"language":"{{language}}"}' {{wirepod_ui}}/api/set_stt_info; echo
    for i in $(seq 1 150); do
      s=$(curl -s {{wirepod_ui}}/api/get_download_status)
      case "$s" in *success*|*error*) echo "model: $s"; break;; esac
      sleep 2
    done
    curl -s "{{wirepod_ui}}/api-chipper/use_ip?port=443"; echo
    echo "restarting again so the voice server on 443 starts..."
    just wirepod-restart

# Point Vector at this wire-pod over SSH (writes /data/data/server_config.json; Vector then needs a Bluetooth sign-in)
[group('wire-pod')]
wirepod-setup-bot:
    #!/usr/bin/env bash
    set -euo pipefail
    vec_ip="$(getent hosts {{vector_host}} | awk '{print $1; exit}')"
    curl -s -F "ip=$vec_ip" -F "key=@{{vector_key}}" {{wirepod_ui}}/api-ssh/setup; echo
    last=""
    for i in $(seq 1 120); do
      s=$(curl -s {{wirepod_ui}}/api-ssh/get_setup_status)
      [ "$s" != "$last" ] && echo "$s"; last="$s"
      case "$s" in done|*error*) break;; esac
      sleep 3
    done
    echo "Next: sign Vector in over Bluetooth (the address on his screen)."

# Connect wire-pod to an OpenAI-compatible LLM (default: local Ollama), with conversation on
[group('wire-pod')]
wirepod-ai model=llm_model endpoint=llm_endpoint:
    curl -s -X POST -H 'Content-Type: application/json' {{wirepod_ui}}/api/set_kg_api -d '{"enable":true,"provider":"custom","key":"ollama","id":"","model":"{{model}}","intentgraph":true,"robotName":"","openai_prompt":"","openai_voice":"","openai_voice_with_english":false,"save_chat":true,"commands_enable":true,"endpoint":"{{endpoint}}","top_p":0,"temp":0}'; echo
    @just wirepod-restart

# Show wire-pod's current AI settings
[group('wire-pod')]
wirepod-ai-show:
    @curl -s {{wirepod_ui}}/api/get_kg_api | python3 -m json.tool

# ---------------------------------------------------------------------------
# Ollama (local LLM on this machine)

# Start Ollama (not enabled at boot)
[group('ollama')]
ollama-start:
    sudo systemctl start ollama
    @systemctl is-active ollama

# Stop Ollama
[group('ollama')]
ollama-stop:
    -sudo systemctl stop ollama

# Download a model: just ollama-pull qwen2.5:7b
[group('ollama')]
ollama-pull model=llm_model:
    ollama pull {{model}}

# Ask the model a question through the same API wire-pod uses
[group('ollama')]
ollama-test question="What is the tallest mountain in Australia?" model=llm_model:
    curl -s -w '\n(%{time_total}s)\n' {{llm_endpoint}}/chat/completions -H 'Content-Type: application/json' -d '{"model":"{{model}}","messages":[{"role":"system","content":"You are a helpful, animated robot called Vector. Keep the response concise yet informative."},{"role":"user","content":"{{question}}"}]}' | python3 -c 'import json,sys; t=sys.stdin.read(); body,_,tail=t.rpartition("\n("); print(json.loads(body)["choices"][0]["message"]["content"]); print("(" + tail)'

# ---------------------------------------------------------------------------
# Tailscale on Vector (experimental; see docs/05-tailscale.md)

# Download, verify and copy the Tailscale ARM build to Vector's /data
[group('tailscale')]
ts-install version=ts_version:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    tgz="tailscale_{{version}}_arm.tgz"
    curl -sSL -o "$tmp/$tgz" "https://pkgs.tailscale.com/stable/$tgz"
    want="$(curl -sSL "https://pkgs.tailscale.com/stable/$tgz.sha256")"
    got="$(sha256sum "$tmp/$tgz" | cut -d' ' -f1)"
    [ "$want" = "$got" ] || { echo "checksum mismatch"; exit 1; }
    tar -xzf "$tmp/$tgz" -C "$tmp"
    {{ssh}} 'mkdir -p /data/tailscale'
    for f in tailscale tailscaled; do
      {{ssh}} "cat > /data/tailscale/$f && chmod 755 /data/tailscale/$f" < "$tmp/tailscale_{{version}}_arm/$f"
    done
    echo "installed Tailscale {{version}} to /data/tailscale"

# Start Tailscale on Vector as a temporary service (a reboot stops it); prints a login URL the first time
[group('tailscale')]
ts-start:
    {{ssh}} 'systemctl is-active -q tailscaled-test || { mkdir -p /run/tailscale; systemd-run --unit=tailscaled-test --property=MemoryMax=96M --setenv=GOMEMLIMIT=48MiB --setenv=GOGC=50 /data/tailscale/tailscaled --state=/data/tailscale/tailscaled.state --statedir=/data/tailscale --socket=/run/tailscale/tailscaled.sock --tun=tailscale0; sleep 5; }'
    {{ssh}} 'timeout 20 /data/tailscale/tailscale --socket=/run/tailscale/tailscaled.sock up --hostname=vector --netfilter-mode=off --accept-dns=false --accept-routes=false || true'

# Show Tailscale status on Vector
[group('tailscale')]
ts-status:
    {{ssh}} '/data/tailscale/tailscale --socket=/run/tailscale/tailscaled.sock status; ps -o rss,comm | grep tailscaled || true'

# Stop Tailscale on Vector (keeps the install and node identity)
[group('tailscale')]
ts-stop:
    -{{ssh}} '/data/tailscale/tailscale --socket=/run/tailscale/tailscaled.sock down; systemctl stop tailscaled-test'

# Point Vector's voice at wire-pod by tailnet name (needs ts-start, and a Tailscale cert on wire-pod: see docs/05)
[group('tailscale')]
ts-use-tailnet name tailnet_ip:
    {{ssh}} 'cd /data/data && cp -n server_config.json server_config.json.lan-backup && cp -n wirepod-cert.crt wirepod-cert.crt.lan-backup'
    {{ssh}} 'grep -q "{{name}}" /etc/hosts || { cp /etc/hosts /data/tailscale/hosts; echo "{{tailnet_ip}} {{name}}" >> /data/tailscale/hosts; mount --bind /data/tailscale/hosts /etc/hosts; }'
    {{ssh}} 'cd /data/data && sed -E "s/\"[0-9.]+(:443|\/ok)/\"{{name}}\1/g" server_config.json.lan-backup > server_config.json && cat server_config.json && systemctl restart anki-robot.target'

# Put Vector's voice back on the LAN setup (restores the .lan-backup files)
[group('tailscale')]
ts-use-lan:
    {{ssh}} 'cd /data/data && cp server_config.json.lan-backup server_config.json && cp wirepod-cert.crt.lan-backup wirepod-cert.crt; grep -q ts.net /etc/hosts && umount /etc/hosts || true; cat server_config.json; systemctl restart anki-robot.target'
