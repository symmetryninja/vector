# 6. Planned session: Vector's voice and LLM over Tailscale, permanently

Status: **in progress** (2026-11-21). Server side done: wire-pod and a small LLM run on the model server, tailnet-only. Robot side (steps 1, 4–8) next.

Background: [03 Voice and AI](03-voice-and-ai.md) (how wire-pod and the LLM fit together) and [05 Tailscale](05-tailscale.md) (the 2026-11-09 experiment that proved it works, and its caveats).

## Goal

Vector can talk to wire-pod and the LLM **from any network**. That keeps working **after reboots** of the robot and the server, and **nothing is exposed to the public internet**.

Done when:
- [x] wire-pod runs on the model server, starts at boot, and uses the server's own LLM endpoint.
- [x] wire-pod's ports are reachable from the tailnet and localhost only, not the LAN.
- [ ] wire-pod presents a Tailscale (Let's Encrypt) certificate for the server's MagicDNS name, renewed automatically.
- [ ] Tailscale on Vector starts at boot from `/data`, as a tagged node, and survives a robot reboot.
- [ ] Vector resolves the server's MagicDNS name after a reboot.
- [ ] Tailnet access rules: Vector can reach only wire-pod's ports (443 voice, 80 check). Only our own devices can reach Vector's SSH.
- [ ] Vector's shared SSH key is replaced by our own.
- [ ] Voice and conversation work at home **and** on another network (e.g. phone hotspot).
- [ ] The desktop wire-pod and Ollama are retired (or kept as a documented fallback).
- [ ] Docs, `justfile` and HISTORY updated.

## Architecture

```
Vector ──(tailnet, WireGuard)──► model server
  vic-cloud                        wire-pod  :443 voice (Tailscale cert), :80 check
  tailscaled (from /data)          LLM server (OpenAI-compatible, localhost only)
                                   tailscaled + cert renewal timer
```

- **wire-pod lives on the model server**, next to the LLM, so the LLM endpoint can stay bound to localhost (or the container network) and is never on the tailnet.
- **The LLM is a small model of its own** ([Qwen3-4B-Instruct-2507](03-voice-and-ai.md#choosing-the-model-2026-11-21), llama.cpp, ~5 GB), always on. A shared big model would make Vector wait behind other jobs, and would change whenever the big model is switched.
- **wire-pod runs with host networking but is firewalled to the tailnet.** It has no authentication, so an nftables rule (`wire-pod/server/wire-pod.nft`, loaded by the unit) lets only `lo` and `tailscale0` reach ports 80, 443 and its web UI. `just wirepod-lan open` lifts it for a robot's first sign-in on the LAN.
- Considered and rejected: wire-pod stays on the desktop and reaches the LLM over the tailnet. It's more moving parts, the desktop has to be always on, and the LLM endpoint would be on the tailnet.

## Before the session (prerequisites)

- [x] The model server's LLM serves an OpenAI-compatible API (`/v1/chat/completions`). Model name: `small`.
- [x] Ports **80 and 443** are free on the model server (a leftover reverse proxy had them), plus a free port for wire-pod's web UI (`WIREPOD_WEB_PORT`).
- [x] HTTPS certificates are enabled in the tailnet.
- [ ] Decide the robot's tailnet login: **interactive login URL** (no secret to store; used in the experiment) or **tagged pre-auth key** (stored only in `local/`, never in git). A tagged node is needed for tag-based access rules either way.
- [ ] Vector is on, on the charger, and reachable (`just find`).

## Session steps

Each step ends with a check. Stop and roll back if a check fails.

### 1. Lock down SSH first (~15 min)

1. Generate our own key (kept outside the repo), add it to Vector's `authorized_keys`, and check we can log in with it.
2. Remove the shared key. Set `VECTOR_KEY` in `local/.env`.
3. Check: login with the shared key fails, and login with ours works.
4. Add recipes: `just ssh-key-install`, `just ssh-key-check`.

### 2. wire-pod and the LLM on the model server ✅ (2026-11-21)

On the server, with this repo cloned and `local/.env` set (`WIREPOD_SYSTEMD=true`, `WIREPOD_WEB_PORT`, `LLM_MODEL`, `LLM_ENDPOINT`):

1. LLM: `just llm-install` (llama.cpp + Qwen3-4B-Instruct-2507 on `127.0.0.1:8085`), or point `LLM_ENDPOINT` at an OpenAI-compatible server you already run. Check: `just llm-test`, `just llm-eval 3`.
2. wire-pod: `just server-install` (Quadlet, firewall, weekly cert timer), then `just wirepod-init` and `just wirepod-ai`.
3. Check: `just wirepod-status` shows 443 and the UI port held by wire-pod, `just wirepod-lan` says closed, and `just wirepod-ai-show` shows the model.

Two bugs in wire-pod's container image, worked around by `server-install` (found 2026-11-21):
- **Settings lost on every restart.** The image keeps its config files in the image and symlinks them into `/data`, but wire-pod saves them by writing a temp file and renaming it, which replaces the symlink with a file inside the container. Quadlet recreates the container on each start, so the settings and robot registrations vanished. `wire-pod/server/run-chipper.sh` starts wire-pod from `/data/chipper` instead, so it writes straight to disk.
- **First-time setup fails with "Service must be vosk or whisper".** The entrypoint creates an empty `apiConfig.json`, which wire-pod can't parse, so it never loads its speech settings; restarting doesn't help. Seeding the file with `{}` fixes it. (Probably what was behind the "restart once" trick in [03](03-voice-and-ai.md).)
- Also: wire-pod ignores SIGTERM as PID 1, so the unit uses `--init` to stop cleanly.

### 3. Tailscale certificate for wire-pod (~20 min)

1. `tailscale cert` for the server's MagicDNS name, written into wire-pod's `certs/` volume (back up the self-signed pair as `*.selfsigned-lan`).
2. A **systemd timer** (weekly) that runs `tailscale cert` and restarts wire-pod only if the cert changed.
3. Check: `openssl s_client -connect <name>:443` shows the Let's Encrypt cert and `Verify return code: 0`.
4. Add recipes: `just ts-cert`, `just ts-cert-status`.

### 4. Point Vector at the new wire-pod (~20 min)

1. `just wirepod-setup-bot` **from the model server** (writes Vector's config with the server's LAN IP, and resets his sign-in).
2. Sign Vector in over Bluetooth. Optionally try wire-pod's built-in BLE pairing to avoid the third-party page, which needs the server's Bluetooth exposed to the container.
3. Check: a voice command works on the LAN.

### 5. Tailscale on Vector, at boot (~45 min; the unknown part)

1. Find a boot hook that lives on `/data` and survives OTAs:
   - check whether WireOS runs anything from `/data/wired/mods` or another `/data` path at boot
   - otherwise a unit in `/etc/systemd/system` (root fs, so it needs re-applying after any OTA; auto-updates are off)
2. The boot script starts `tailscaled` (memory-capped, as in the experiment), then:
   - bind-mounts a hosts file with the server's MagicDNS name → tailnet IP over `/etc/hosts`
   - restarts `anki-robot.target` once Tailscale is up, so `vic-cloud` connects
3. `tailscale up --hostname=vector --advertise-tags=tag:vector --netfilter-mode=off --accept-dns=false --accept-routes=false`
4. Turn off key expiry for the `vector` node, or rely on the tag.
5. Add recipes: `just ts-install-boot`, `just ts-remove-boot`.
6. Check: **reboot Vector**, then `just ts-status` shows him online, without logging in.

### 6. Switch Vector to the tailnet name (~15 min)

1. `just ts-use-tailnet <name> <tailnet-ip>` (appends the Let's Encrypt chain, writes the config, and keeps the `.lan-backup` files).
2. Check: voice works. Then **reboot Vector** and check it again.

### 7. Tailnet access rules (~20 min)

1. In the Tailscale policy:
   - `tag:vector` → model server, ports 443 and 80 only
   - our devices → `tag:vector`, port 22 only, plus his `:8080` settings page if wanted
2. Check from Vector: the model server's 443 is reachable, and other tailnet hosts aren't. Check from a non-admin device: Vector isn't reachable.

### 8. Away-from-home test (~15 min)

1. Move Vector to another network (phone hotspot) using `just wifi-add` beforehand.
2. Check: voice and conversation work. `tailscale ping vector` shows a DERP or direct path.
3. Note latency and any dropouts.

### 9. Wrap up (~15 min)

- Retire the desktop's wire-pod and Ollama (`just down`), or document them as a fallback.
- Update the docs (01, 03, 05, this file → "done"), the `justfile`, the README and HISTORY. Commit.

## Rollback

At any point: `just ts-use-lan` (restores Vector's LAN config and cert), then `just ts-remove-boot`, and restart the desktop wire-pod with `just up`. The `.lan-backup` and `*.selfsigned-lan` files must exist before step 6.

## Open questions

- Is there a WireOS-supported boot hook on `/data`? (Ask in the os-vector community if it's not obvious from the source.)
- How do battery, temperature and CPU look with `tailscaled` running all day?
- Does `vic-cloud` reconnect by itself if Tailscale starts after it, or does the boot script have to restart `anki-robot.target`?
- What does wire-pod do when the LLM is slow or down: does Vector time out gracefully?
- Is the face-enrolment problem (doc 03) still present after the move? It's unrelated, but worth a retry while he's on the charger.
