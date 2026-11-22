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
llm_model := env("LLM_MODEL", "small")
llm_endpoint := env("LLM_ENDPOINT", "http://127.0.0.1:8085/v1")
# Server install (docs/06): where wire-pod's data and scripts live, and whether it runs as a systemd unit
wirepod_dir := env("WIREPOD_DIR", "/srv/wire-pod")
wirepod_systemd := env("WIREPOD_SYSTEMD", "false")
llm_models := env("LLM_MODELS_DIR", "/srv/models")
ts_version := env("TS_VERSION", "1.104.5")
# The wire-pod server's tailnet name and IP (private: set in local/.env)
server_ts_name := env("SERVER_TS_NAME", "")
server_ts_ip := env("SERVER_TS_IP", "")

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

# Replace the SSH key every unlocked bot shares with your own (generates one if missing). Backs up the old file on /data
[group('privacy')]
ssh-key-install newkey=(home_directory() / ".ssh/vector_ed25519"):
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f "{{newkey}}" ] || ssh-keygen -q -t ed25519 -N '' -C vector-owner -f "{{newkey}}"
    pub="$(cat "{{newkey}}.pub")"
    {{ssh}} "cp -n /etc/ssh/authorized_keys /data/etc/authorized_keys.shared-backup; mount -o rw,remount / && grep -qF '$pub' /etc/ssh/authorized_keys || echo '$pub' >> /etc/ssh/authorized_keys; mount -o ro,remount /"
    ssh -i "{{newkey}}" -o IdentitiesOnly=yes -o BatchMode=yes root@{{vector_host}} true || { echo "new key doesn't work; shared key left in place"; exit 1; }
    {{ssh}} "mount -o rw,remount / && echo '$pub' > /etc/ssh/authorized_keys.new && mv /etc/ssh/authorized_keys.new /etc/ssh/authorized_keys && chmod 600 /etc/ssh/authorized_keys; mount -o ro,remount /"
    echo "Only {{newkey}} works now. Set VECTOR_KEY={{newkey}} in local/.env. (An OTA restores the shared key.)"
    just ssh-key-check "{{newkey}}"

# Check that the shared key is refused and yours works: just ssh-key-check ~/.ssh/vector_ed25519 [shared-key]
[group('privacy')]
ssh-key-check newkey=vector_key shared=(home_directory() / ".ssh/vector_private_key"):
    #!/usr/bin/env bash
    o="-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa"
    if [ -f "{{shared}}" ]; then ssh -i "{{shared}}" $o root@{{vector_host}} true 2>/dev/null && echo "shared key: STILL WORKS" || echo "shared key: refused"; fi
    ssh -i "{{newkey}}" $o root@{{vector_host}} true 2>/dev/null && echo "your key: works" || echo "your key: FAILS"

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
    vec_ip="$(getent ahostsv4 {{vector_host}} | awk '{print $1; exit}')"
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
    {{ if wirepod_systemd == "true" { "sudo systemctl start wire-pod" } else { "sudo " + engine + " start wire-pod" } }}
    @sleep 10

# Stop wire-pod
[group('wire-pod')]
wirepod-stop:
    -{{ if wirepod_systemd == "true" { "sudo systemctl stop wire-pod" } else { "sudo " + engine + " stop -t 10 wire-pod" } }}

# Restart wire-pod
[group('wire-pod')]
wirepod-restart:
    {{ if wirepod_systemd == "true" { "sudo systemctl restart wire-pod" } else { "sudo " + engine + " restart -t 5 wire-pod" } }}
    @sleep 10
    @just wirepod-status

# Follow wire-pod's log
[group('wire-pod')]
wirepod-logs:
    {{ if wirepod_systemd == "true" { "sudo journalctl -fu wire-pod -n 50" } else { "sudo " + engine + " logs -f --tail 50 wire-pod" } }}

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
    vec_ip="$(getent ahostsv4 {{vector_host}} | awk '{print $1; exit}')"
    curl -s -F "ip=$vec_ip" -F "key=@{{vector_key}}" {{wirepod_ui}}/api-ssh/setup; echo
    last=""
    for i in $(seq 1 120); do
      s=$(curl -s {{wirepod_ui}}/api-ssh/get_setup_status)
      [ "$s" != "$last" ] && echo "$s"; last="$s"
      case "$s" in done|*error*) break;; esac
      sleep 3
    done
    echo "Next: sign Vector in over Bluetooth (the address on his screen)."

# EXPERIMENTAL: sign Vector in over the wire-pod server's own Bluetooth. On WireOS 3.0.2 it crashes vic-switchboard (fault 913); use the browser page for now (docs/06 section 5)
[group('wire-pod')]
wirepod-ble-signin name="Vector":
    #!/usr/bin/env bash
    set -euo pipefail
    ui="{{wirepod_ui}}"
    api() { curl -s -m "${2:-30}" "$ui/api-ble/$1"; }
    # wire-pod's own page calls get_robot_status after the PIN, which for unlocked (WireOS) robots asks
    # for his Wi-Fi IP over Bluetooth with no timeout and wedges wire-pod's Bluetooth until a restart.
    # This does only what sign-in needs: init, scan, connect, PIN, auth.
    if ! r=$(api init 15); then
      echo "wire-pod's Bluetooth is stuck (no answer from init). Restart wire-pod (just wirepod-restart, on the server) and run this again."; exit 1
    fi
    echo "init: $r"
    case "$r" in *success*) ;; *) exit 1;; esac
    echo "scanning..."
    scan=$(api scan 60)
    id=$(printf '%s' "$scan" | python3 -c 'import json,sys; n=sys.argv[1].lower(); b=[x for x in json.load(sys.stdin) if n in x["name"].lower()]; print(b[0]["id"] if b else "")' "{{name}}")
    [ -n "$id" ] || { echo "no robot named '{{name}}' found: $scan"; exit 1; }
    echo "connecting to robot $id..."
    r=$(api "connect?id=$id" 60); echo "connect: $r"
    case "$r" in *success*) ;; *) exit 1;; esac
    echo "Double-press Vector's back button: he shows a PIN on his screen."
    read -rp "PIN: " pin
    r=$(api "send_pin?pin=$pin" 60); echo "pin: $r"
    case "$r" in *success*) ;; *) exit 1;; esac
    echo "authenticating..."
    r=$(api do_auth 120); echo "auth: $r"
    api disconnect 15 >/dev/null || true
    case "$r" in *success*) echo "Signed in. Try: Hey Vector, what time is it?";; *) exit 1;; esac

# Connect wire-pod to an OpenAI-compatible LLM (llama.cpp server, Ollama, ...), with conversation on
[group('wire-pod')]
wirepod-ai model=llm_model endpoint=llm_endpoint:
    curl -s -X POST -H 'Content-Type: application/json' {{wirepod_ui}}/api/set_kg_api -d '{"enable":true,"provider":"custom","key":"none","id":"","model":"{{model}}","intentgraph":true,"robotName":"","openai_prompt":"","openai_voice":"","openai_voice_with_english":false,"save_chat":true,"commands_enable":true,"endpoint":"{{endpoint}}","top_p":0,"temp":0}'; echo
    @just wirepod-restart

# Show wire-pod's current AI settings
[group('wire-pod')]
wirepod-ai-show:
    @curl -s {{wirepod_ui}}/api/get_kg_api | python3 -m json.tool

# ---------------------------------------------------------------------------
# LLM (any OpenAI-compatible endpoint; see docs/03 "Choosing the model")

# Ask the model a question through the same API wire-pod uses
[group('llm')]
llm-test question="What is the tallest mountain in Australia?" model=llm_model endpoint=llm_endpoint:
    curl -s -w '\n(%{time_total}s)\n' {{endpoint}}/chat/completions -H 'Content-Type: application/json' -d '{"model":"{{model}}","messages":[{"role":"system","content":"You are a helpful, animated robot called Vector. Keep the response concise yet informative."},{"role":"user","content":"{{question}}"}]}' | python3 -c 'import json,sys; t=sys.stdin.read(); body,_,tail=t.rpartition("\n("); print(json.loads(body)["choices"][0]["message"]["content"]); print("(" + tail)'

# Test a model on wire-pod's real prompt and command syntax: just llm-eval 3 small=http://127.0.0.1:8085/v1
[group('llm')]
llm-eval runs="1" *models=(llm_model + "=" + llm_endpoint):
    python3 -I llm/eval-wirepod-prompt.py --runs {{runs}} {{models}}

# ---------------------------------------------------------------------------
# Ollama (optional: a local LLM on a desktop; the server uses llama.cpp instead)

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

# ---------------------------------------------------------------------------
# Server (always-on wire-pod on the tailnet; run these ON the server. See docs/06)

# Install wire-pod as a systemd service (Quadlet), tailnet + localhost only, with weekly cert renewal
[group('server')]
server-install:
    #!/usr/bin/env bash
    set -euo pipefail
    dir="{{wirepod_dir}}"
    for p in 80 443 {{wirepod_web_port}}; do
      owner="$(sudo ss -tlnpH "sport = :$p" | grep -o '(("[^"]*"' | head -1 | tr -d '("' || true)"
      [ -z "$owner" ] || [ "$owner" = chipper ] || { echo "port $p is taken by $owner"; exit 1; }
    done
    sudo mkdir -p "$dir/data/images" "$dir/data/chipper"
    sudo install -m 755 wire-pod/server/run-chipper.sh wire-pod/server/cert.sh "$dir/"
    sudo install -m 644 wire-pod/server/wire-pod.nft "$dir/"
    sudo sed -i 's/tcp dport { 80, 443, [0-9]* }/tcp dport { 80, 443, {{wirepod_web_port}} }/' "$dir/wire-pod.nft"
    # The image creates an empty apiConfig.json, which wire-pod can't parse ("Service must be vosk or whisper")
    sudo test -s "$dir/data/chipper/apiConfig.json" || echo '{}' | sudo tee "$dir/data/chipper/apiConfig.json" >/dev/null
    sudo install -m 644 wire-pod/server/apparmor/wire-pod-bluetooth /etc/apparmor.d/wire-pod-bluetooth
    sudo apparmor_parser -r /etc/apparmor.d/wire-pod-bluetooth
    ts_name="$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
    sudo mkdir -p /etc/containers/systemd
    sed -e "s#@DIR@#$dir#g" -e "s#@WEB_PORT@#{{wirepod_web_port}}#g" -e "s#@TS_NAME@#$ts_name#g" wire-pod/server/wire-pod.container | sudo tee /etc/containers/systemd/wire-pod.container >/dev/null
    printf '[Unit]\nDescription=Renew wire-pod Tailscale certificate\n\n[Service]\nType=oneshot\nExecStart=%s/cert.sh\n' "$dir" | sudo tee /etc/systemd/system/wire-pod-cert.service >/dev/null
    printf '[Unit]\nDescription=Renew wire-pod Tailscale certificate weekly\n\n[Timer]\nOnCalendar=weekly\nRandomizedDelaySec=6h\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' | sudo tee /etc/systemd/system/wire-pod-cert.timer >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable --now wire-pod-cert.timer
    sudo systemctl restart wire-pod
    echo "wire-pod installed. Next: just wirepod-init, then just wirepod-ai (set WIREPOD_SYSTEMD=true in local/.env)"

# Install the small LLM (llama.cpp + Qwen3-4B-Instruct-2507) as a systemd service on 127.0.0.1:8085
[group('server')]
llm-install:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo mkdir -p "{{llm_models}}"
    f="{{llm_models}}/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
    sudo test -f "$f" || sudo curl -fL -o "$f" https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf
    sudo mkdir -p /etc/containers/systemd
    sed "s#@MODELS@#{{llm_models}}#g" llm/small-llm.container | sudo tee /etc/containers/systemd/small-llm.container >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl restart small-llm
    echo "waiting for the model to load..."
    for i in $(seq 60); do curl -sf 127.0.0.1:8085/health >/dev/null && break; sleep 2; done
    just llm-test

# Let the LAN reach wire-pod (open), or only the tailnet (close). Open is needed once, for a robot's first sign-in
[group('server')]
wirepod-lan action="status":
    #!/usr/bin/env bash
    case "{{action}}" in
      open)   sudo nft delete table inet wirepod 2>/dev/null || true; echo "LAN open until 'close' or a wire-pod restart";;
      close)  sudo nft delete table inet wirepod 2>/dev/null || true; sudo nft -f "{{wirepod_dir}}/wire-pod.nft"; echo "tailnet + localhost only";;
      status) sudo nft list table inet wirepod >/dev/null 2>&1 && echo "closed: tailnet + localhost only" || echo "OPEN to the LAN";;
      *)      echo "usage: just wirepod-lan open|close|status"; exit 1;;
    esac

# Switch wire-pod to a Tailscale certificate for this server's MagicDNS name (keeps the LAN cert as *.selfsigned-lan)
[group('server')]
wirepod-ts-cert:
    sudo sh -c 'cd "{{wirepod_dir}}/data/certs" && cp -n cert.crt cert.crt.selfsigned-lan && cp -n cert.key cert.key.selfsigned-lan'
    sudo "{{wirepod_dir}}/cert.sh"

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

# Start Tailscale on Vector at every boot, and resolve the server's tailnet name (units on / call files on /data; re-run after an OTA)
[group('tailscale')]
ts-install-boot name=server_ts_name ip=server_ts_ip:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -n "{{name}}" ] && [ -n "{{ip}}" ] || { echo "set SERVER_TS_NAME and SERVER_TS_IP in local/.env"; exit 1; }
    # Hosts file on /data: the robot's own /etc/hosts plus the server's tailnet name (his DNS can't resolve .ts.net)
    {{ssh}} 'grep -q ts.net /etc/hosts && umount /etc/hosts 2>/dev/null; grep -v ts.net /etc/hosts > /data/tailscale/hosts; echo "{{ip}} {{name}}" >> /data/tailscale/hosts'
    {{ssh}} 'systemctl stop tailscaled-test 2>/dev/null || true; mount -o rw,remount / && cat > /etc/systemd/system/vector-tailscaled.service && mount -o ro,remount /' <<'UNIT'
    [Unit]
    Description=Tailscale on Vector (binary and state on /data)
    After=network.target connman.service
    # If ConnMan restarts (it can crash while switching Wi-Fi), it sets tailscale0 down; restart with it
    PartOf=connman.service
    RequiresMountsFor=/data

    [Service]
    ExecStartPre=/bin/mkdir -p /run/tailscale
    ExecStart=/data/tailscale/tailscaled --state=/data/tailscale/tailscaled.state --statedir=/data/tailscale --socket=/run/tailscale/tailscaled.sock --tun=tailscale0
    Environment=GOMEMLIMIT=48MiB GOGC=50
    MemoryMax=96M
    Restart=on-failure
    RestartSec=10

    [Install]
    WantedBy=multi-user.target
    UNIT
    {{ssh}} 'mount -o rw,remount / && cat > /etc/systemd/system/vector-hosts.service && mount -o ro,remount /' <<'UNIT'
    [Unit]
    Description=Resolve the wire-pod server's tailnet name (hosts file on /data)
    RequiresMountsFor=/data
    Before=anki-robot.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    # /data is an encrypted volume that can appear after this unit is first considered, so wait
    # for the file (up to 60 s) rather than use ConditionPathExists, which skipped it at boot.
    ExecStart=/bin/sh -c 'for i in $(seq 60); do [ -f /data/tailscale/hosts ] && exec /bin/mount --bind /data/tailscale/hosts /etc/hosts; sleep 1; done; echo "no /data/tailscale/hosts"; exit 1'
    ExecStop=/bin/umount /etc/hosts

    [Install]
    WantedBy=multi-user.target
    UNIT
    # ConnMan manages every interface it isn't told to ignore, and on (re)start it sets tailscale0 DOWN,
    # which silently breaks the tailnet. Add "tailscale" to its default ignore list (backup on /data).
    {{ssh}} 'f=/etc/connman/main.conf; cp -n $f /data/etc/connman-main.conf.orig; grep -q "^NetworkInterfaceBlacklist" $f || { mount -o rw,remount / && echo "NetworkInterfaceBlacklist = vmnet,vboxnet,virbr,ifb,ve-,vb-,tailscale" >> $f; mount -o ro,remount /; }; grep NetworkInterfaceBlacklist $f'
    # WireOS's own firewall (iptables.service, /etc/iptables/iptables.rules) drops all outgoing traffic
    # except on wlan0/lo/tether. Allow it out on tailscale0 too, and re-add that whenever WireOS reloads
    # its rules (a reload wipes rules added by hand). Incoming stays as WireOS defines it.
    {{ssh}} 'mount -o rw,remount / && cat > /etc/systemd/system/vector-tailnet-fw.service && mount -o ro,remount /' <<'UNIT'
    [Unit]
    Description=Let Vector's firewall send traffic over Tailscale (tailscale0)
    After=iptables.service
    PartOf=iptables.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/bin/sh -c 'iptables -C OUTPUT -o tailscale0 -j ACCEPT 2>/dev/null || iptables -I OUTPUT -o tailscale0 -j ACCEPT; ip6tables -C OUTPUT -o tailscale0 -j ACCEPT 2>/dev/null || ip6tables -I OUTPUT -o tailscale0 -j ACCEPT'
    ExecStop=/bin/sh -c 'iptables -D OUTPUT -o tailscale0 -j ACCEPT; ip6tables -D OUTPUT -o tailscale0 -j ACCEPT; true'

    [Install]
    WantedBy=multi-user.target iptables.service
    UNIT
    {{ssh}} 'mount -o rw,remount / && systemctl daemon-reload && systemctl enable vector-tailscaled vector-hosts vector-tailnet-fw; mount -o ro,remount /; systemctl restart vector-tailnet-fw; systemctl restart vector-hosts; systemctl restart vector-tailscaled; sleep 8; systemctl is-active vector-tailscaled vector-hosts; grep ts.net /etc/hosts'
    just ts-status

# Undo ts-install-boot: stop Tailscale and the hosts entry, remove the units (keeps /data/tailscale)
[group('tailscale')]
ts-remove-boot:
    {{ssh}} 'systemctl stop vector-tailscaled vector-hosts vector-tailnet-fw; mount -o rw,remount / && systemctl disable vector-tailscaled vector-hosts vector-tailnet-fw; rm -f /etc/systemd/system/vector-tailscaled.service /etc/systemd/system/vector-hosts.service /etc/systemd/system/vector-tailnet-fw.service; [ -f /data/etc/connman-main.conf.orig ] && cp /data/etc/connman-main.conf.orig /etc/connman/main.conf; systemctl daemon-reload; mount -o ro,remount /; echo removed'

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
