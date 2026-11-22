# 6. Vector's voice and LLM over Tailscale, permanently

Status: **done** (2026-11-21/22). wire-pod and a small LLM run on an always-on home server, reachable only over the tailnet. Vector runs Tailscale at boot and talks to wire-pod by its MagicDNS name. Voice and conversation work at home, after a reboot, and away from home on a phone hotspot over mobile data.

Background: [03 Voice and AI](03-voice-and-ai.md) (how wire-pod and the LLM fit together) and [05 Tailscale](05-tailscale.md) (the 2026-11-09 experiment that proved it works, and why not Funnel).

In this doc, `<server>.<tailnet>.ts.net` / `<server-ts-ip>` are the server's MagicDNS name and tailnet IP. Real values live in `local/.env` (`SERVER_TS_NAME`, `SERVER_TS_IP`, `VECTOR_HOST`).

## Goal

Vector can talk to wire-pod and the LLM **from any network**. That keeps working **after reboots** of the robot and the server, and **nothing is exposed to the public internet**.

- [x] wire-pod runs on the server, starts at boot, and uses the server's own LLM endpoint.
- [x] wire-pod's ports are reachable from the tailnet and localhost only, not the LAN.
- [x] wire-pod presents a Tailscale (Let's Encrypt) certificate for the server's MagicDNS name, renewed weekly.
- [x] Tailscale on Vector starts at boot from `/data`, as a tagged node, and survives a robot reboot.
- [x] Vector resolves the server's MagicDNS name after a reboot.
- [x] Tailnet access rules: Vector can reach only wire-pod's ports (443 voice, 80 check).
- [x] Vector's shared SSH key is replaced by our own.
- [x] Voice and conversation work at home, over the tailnet, and after a reboot.
- [x] Voice and conversation work on another network (phone hotspot on mobile data).
- [x] The desktop wire-pod and Ollama are retired (kept documented in 03 as the first version).

## Architecture

```
Vector ──(tailnet, WireGuard)──► server
  vic-cloud                        wire-pod  :443 voice (Tailscale cert), :80 check, web UI
  tailscaled (from /data)          small LLM (OpenAI-compatible, localhost only)
  hosts entry for the server       nftables: wire-pod ports from lo + tailscale0 only
```

- **wire-pod lives on the server**, next to the LLM, so the LLM stays on localhost and is never on the tailnet.
- **The LLM is a small model of its own** ([Qwen3-4B-Instruct-2507](03-voice-and-ai.md#choosing-the-model-2026-11-21), llama.cpp, ~5 GB), always on. A shared big model would make Vector wait behind other jobs.
- **wire-pod uses host networking but is firewalled to the tailnet.** It has no authentication, so `wire-pod/server/wire-pod.nft` lets only `lo` and `tailscale0` reach ports 80, 443 and its web UI. Vector uses Tailscale even at home; Tailscale finds the direct LAN path, so it costs nothing there.

## How it was done

Commands run on the server unless they say "robot". Settings come from `local/.env` (see `env.example`).

### 1. The LLM and wire-pod on the server

1. LLM: `just llm-install` (llama.cpp + Qwen3-4B-Instruct-2507 on `127.0.0.1:8085`), or point `LLM_ENDPOINT` at an OpenAI-compatible server you already run. Check: `just llm-test`, `just llm-eval 3`.
2. wire-pod: `just server-install` (Quadlet unit, firewall rule, AppArmor profile, weekly cert timer), then `just wirepod-init` and `just wirepod-ai`. Set `WIREPOD_SYSTEMD=true` so the `wirepod-*` recipes use systemctl.
3. Check: `just wirepod-status` (443 and the UI port held by wire-pod), `just wirepod-lan` (closed), `just wirepod-ai-show`.

Problems in wire-pod's container image, all handled by `server-install`:
- **Settings lost on every restart.** The image keeps its config files in the image and symlinks them into `/data`, but wire-pod saves by writing a temp file and renaming it, which replaces the symlink with a file inside the container. Quadlet recreates the container on each start, so settings and robot registrations vanished. `wire-pod/server/run-chipper.sh` starts wire-pod from `/data/chipper`, so it writes straight to disk.
- **First-time setup fails with "Service must be vosk or whisper".** The entrypoint creates an empty `apiConfig.json`, which wire-pod can't parse, so it never loads its speech settings, and restarting doesn't help. Seeding the file with `{}` fixes it. (Probably what was behind the "restart once" trick in [03](03-voice-and-ai.md).)
- **"forbidden host"** when opening the web UI by MagicDNS name: wire-pod's guard against DNS rebinding only accepts IPs, single-word and `.local`/`.lan`-style names. The unit sets `WIREPOD_ALLOWED_HOSTS` to the server's tailnet name; other names are still refused.
- wire-pod ignores SIGTERM as PID 1, so the unit uses `--init`.
- If the server's LLM sits behind a proxy, make sure it **streams**: wire-pod speaks sentence by sentence as text arrives.

### 2. Replace the shared SSH key (robot)

Every unlocked bot accepts the same publicly known key, in `/etc/ssh/authorized_keys` (read-only root, restored by an OTA).

- `just ssh-key-install` generates `~/.ssh/vector_ed25519`, adds it, checks it works, then removes the shared key (backup: `/data/etc/authorized_keys.shared-backup`). `just ssh-key-check` confirms the shared key is refused.
- Set `VECTOR_KEY` to the new key. After any OTA, run it again.

### 3. Tailscale at boot (robot)

WireOS has **no supported hook that runs scripts from `/data` at boot**. `/data/wired/mods` holds settings for WireOS's own daemon, not scripts. So small systemd units go on the root filesystem, and everything they run stays on `/data`. `just ts-install-boot` installs them; re-run it after an OTA (auto-updates are off).

- `vector-tailscaled.service` runs `/data/tailscale/tailscaled` (memory-capped: `MemoryMax=96M`, `GOMEMLIMIT=48MiB`). The node state on `/data` reconnects it by itself, no login needed. If an earlier `tailscale down` is saved in the state, run `tailscale up` once.
- `vector-hosts.service` bind-mounts `/data/tailscale/hosts` (his own hosts file plus `<server-ts-ip> <server>.<tailnet>.ts.net`) over `/etc/hosts` before the robot software starts. His DNS can't resolve `.ts.net` names.
- **Gotcha:** the first version used `ConditionPathExists=/data/tailscale/hosts`. `/data` is an encrypted volume that wasn't readable yet when systemd checked, so the unit was skipped at boot. Vector couldn't resolve the server and sat on his loading screen. The unit now waits up to 60 s for the file.
- **Gotcha (found 2026-11-22, after the hotspot test):** voice stopped working although Tailscale showed him online and `tailscale ping` worked. Two things in WireOS break `tailscale0` after a network change, and `ts-install-boot` now handles both:
  - **ConnMan** (his network manager) crashed while switching Wi-Fi networks, and when systemd restarted it, it took over `tailscale0` and set it DOWN. `tailscaled` didn't notice ("Failed to write packets to TUN device"). Fixes: `tailscale` is added to ConnMan's `NetworkInterfaceBlacklist` in `/etc/connman/main.conf` (original backed up on `/data`), and `vector-tailscaled` has `PartOf=connman.service`, so it restarts with ConnMan.
  - **WireOS's own firewall** (`iptables.service`, `/etc/iptables/iptables.rules`) has default-DROP policies and only lets traffic *out* on `wlan0`, `lo` and `tether`. It was re-applied at that ConnMan restart, and from then on nothing could leave over `tailscale0` (`ping: sendto: Operation not permitted`). Why it hadn't blocked Tailscale before that is still to confirm. Fix: a third unit, `vector-tailnet-fw.service`, adds `OUTPUT -o tailscale0 ACCEPT` and is tied to `iptables.service`, so it's re-added whenever WireOS reloads its rules. Incoming stays as WireOS defines it (SSH, 443, 8080 and replies); Tailscale's access rules decide who can reach him.
  - After fixing it, a voice connection stuck from before needed `just restart-robot`.
- WireOS reboots him **every night** (`rebooter.sh`, between 1 and 5 am once he's been up 4 hours), so boot-time start really matters.
- Cost: `tailscaled` uses ~25–30 MB of his ~474 MB RAM.

### 4. Certificate and pointing Vector at the server (no LAN step needed)

Order matters, and it avoids ever opening wire-pod to the LAN:

1. `just wirepod-ts-cert`: wire-pod presents a Let's Encrypt cert for `<server>.<tailnet>.ts.net` (its own LAN cert is kept as `*.selfsigned-lan`). The cert file holds the full chain.
2. `just wirepod-setup-bot` (over the tailnet is fine: wire-pod SSHes out to the robot). It copies wire-pod's cert file to the robot as `/data/data/wirepod-cert.crt`, and with it the chain, so renewals keep working. It always writes the server's **LAN IP** into the robot's `server_config.json`, and it resets his sign-in and reboots him.
3. `just ts-use-tailnet <server>.<tailnet>.ts.net <server-ts-ip>`: rewrites `server_config.json` to the name (backup: `.lan-backup`) and restarts the robot software.
4. Sign him in over Bluetooth (next section).

Check: from the robot, `curl --cacert /data/data/wirepod-cert.crt https://<server>.<tailnet>.ts.net/` verifies (`ssl_verify_result` 0).

### 5. Bluetooth sign-in

What worked: **the browser page** his screen shows (`wp.pvic.xyz`, a copy of DDL's BLE setup page) in Chrome with Web Bluetooth. That page only sends a dummy login to its own server; the real sign-in is between Vector and our wire-pod.

What was tried first: **wire-pod's built-in Bluetooth sign-in from the server**, so no third-party page is needed. On Linux it uses the host's BlueZ over the system D-Bus, so the unit mounts `/run/dbus/system_bus_socket` and runs under `wire-pod/server/apparmor/wire-pod-bluetooth`: Podman's default container profile plus D-Bus to BlueZ only (the default profile blocks D-Bus). Scanning and pairing work (**double-press Vector's back button** to show the PIN). But on WireOS 3.0.2:

- **wire-pod's own page hangs.** After the PIN it asks for the robot's status, and for an unlocked robot it then asks for his Wi-Fi IP over Bluetooth with **no timeout**. Vector never answers, so that request holds wire-pod's Bluetooth lock forever. Vector gives up, and every later Bluetooth request (including the page's "Checking if wire-pod can use BLE directly...") hangs until wire-pod restarts. Found with a Go stack dump (`kill -QUIT` the `chipper` process).
- **`just wirepod-ble-signin`** skips that call (init, scan, connect, PIN, auth only). It got further, but **crashed `vic-switchboard` on the robot** straight after the encrypted channel was set up and two status requests were answered. His fault handler restarted the robot software with **fault code 913**. The crash dump is in `/data/data/com.anki.victor/cache/crashDumps/`. Not investigated further; possibly a protocol mismatch between wire-pod's `vector-bluetooth` library and WireOS's switchboard.

So for now: sign in with the browser page. The built-in route needs the robot in Bluetooth range of the server, and is worth retrying with newer wire-pod/WireOS versions.

### 6. Tailnet access rules

Goal: Vector can reach only wire-pod (443 voice, 80 check) on the server. Your own devices keep full access, including SSH to Vector, and the server can still reach Vector (wire-pod connects back to him on 443 and SSHes in for setup).

```json
{
  "tagOwners": { "tag:vector": ["autogroup:admin"] },
  "grants": [
    { "src": ["autogroup:member"], "dst": ["*"], "ip": ["*"] },
    { "src": ["tag:vector"], "dst": ["<server-ts-ip>"], "ip": ["tcp:443", "tcp:80"] }
  ]
}
```

Then tag the robot (admin console → Machines → `vector` → Edit ACL tags → `tag:vector`). Tagged nodes don't expire.

Gotchas:
- The default policy's allow-all rule has source `*` (everyone), which **includes tagged devices**. Change it to `autogroup:member`, or the tag restricts nothing. We found this by testing: before the change, Vector could still reach Home Assistant.
- The allow-all rule's **destination must stay `*`**. "Members' devices" doesn't include tagged devices, so your machines (and wire-pod) would lose access to Vector.
- If you've **shared** a device with someone outside the tailnet, they're not members. Check they can still reach it, and give them their own rule if not.
- On the free plan the admin console may only offer the visual editor. Tags are created there, and a plain IP works as a destination, so no `hosts` entry is needed.
- Don't tag the server: a tagged device loses the access it had as your device for connections it starts (wire-pod → Vector, anything else the server reaches).

Check from the robot: `curl` the server's 443 and 80 (answer), and the server's other ports and other tailnet devices (no answer). BusyBox `nc` on the robot can't do port checks; use `curl`.

### 7. Reboot test

`just reboot`. One minute later, with nothing done by hand: `vector-tailscaled` and `vector-hosts` active, the hosts entry present, `vic-cloud` connected to wire-pod over the tailnet, and voice and conversation working. The first command after a reboot took a few seconds (probably Tailscale finding the direct path and the first TLS connection); later ones are quick.

### 8. Away-from-home test ✅ (2026-11-22)

1. Add the network beforehand: `just wifi-add` (interactive `connmanctl`). Saved networks live in `/data/lib/connman/`, so they survive reboots and OTAs.
2. Set `VECTOR_HOST` to his tailnet name so the `just` robot recipes work on any network.
3. Move Vector to the phone hotspot (`connmanctl connect <service>` over SSH works; the session drops and you reconnect over the tailnet). Tailscale reconnected by itself within a minute.
4. **Turn the phone's own Wi-Fi off.** With it on, the hotspot shares the home Wi-Fi and Tailscale's path still goes through the home LAN, so it isn't a real away test.

Result: Tailscale went **direct over the mobile network** (the carrier's public address, no relay), ~365 ms round trip against ~5 ms at home. Voice commands and conversation worked with no noticeable delay. To bring him home, turn the hotspot off: he goes back to a saved home network.

## Rollback

`just ts-use-lan` (restores the `.lan-backup` config), `just ts-remove-boot`, and `just wirepod-lan open` on the server, or point him at another wire-pod with `just wirepod-setup-bot`.

## Open questions

- Battery, temperature and CPU with `tailscaled` running all day.
- What wire-pod does when the LLM is slow or down: does Vector time out gracefully?
- Why `vic-switchboard` crashes on wire-pod's built-in Bluetooth sign-in (fault 913), and whether a self-hosted copy of the browser setup page is the better long-term route.
- The face-enrolment problem from doc 03.
