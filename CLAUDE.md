# CLAUDE.md

Guidance for Claude Code (and humans) working in this repo. It manages a real Anki Vector robot on WireOS, a self-hosted wire-pod voice server, and a local LLM. Read [README.md](README.md) first for the current state.

## Repo conventions

- **Public repo: never commit private data.** No keys, passwords, Wi-Fi names, IPs, MACs, robot serials/ESNs/names, tailnet names or API keys, in files, commit messages or HISTORY. Use placeholders (`<vector-ip>`, `<host>.<tailnet>.ts.net`). Real values live in `local/.env` (gitignored; see `env.example`). Grep the diff for addresses and names before committing.
- **Commit as the GitHub noreply address** (`4994379+symmetryninja@users.noreply.github.com`), never a personal email. A fresh clone has no repo-local identity and picks up the global one, so after cloning run `git config --local user.email 4994379+symmetryninja@users.noreply.github.com`. Check with `git log origin/main..HEAD --format=%ae` before pushing.
- **`HISTORY.md`**: add a dated, plain-language entry for every meaningful step (what was done and why, not commands). Newest at the bottom, grouped by date heading.
- **`docs/0N-*.md`**: one doc per goal. Keep each `Status:` line and the table in `docs/README.md` accurate. Record findings with dates under `## Findings`; mark anything unverified as "to confirm".
- **Commit and push to `main` freely.** Keep docs and `HISTORY.md` current as work happens, without asking first. Still ask before force-pushes or history rewrites.
- **`justfile`** is the toolbox. If you do something on the robot or server more than once, add a recipe (grouped, commented, settings via `env()`), then run `just --list` and `just --dry-run <recipe>` to check it.

## Working on the robot (WireOS)

- Reach him with `just ssh '<command>'` (it quotes the command so it all runs on the robot). Address and key come from `VECTOR_HOST` / `VECTOR_KEY`. Older images need `ssh-rsa` host keys (already in the recipe).
- **`/` is read-only and replaced by OTAs.** Persistent changes go on `/data`. If you must touch `/`, use `mount -o rw,remount /` … `mount -o ro,remount /`, and document that an OTA undoes it.
- **Restart the robot software as a group**: `just restart-robot` (`systemctl restart anki-robot.target`). Restarting `vic-cloud` alone leaves it stuck retrying `/dev/socket/_switchboard_gateway_server_`.
- **Privacy rule:** the microphone must not send audio to any service the owner doesn't control. Before (re)enabling `vic-cloud`, check `/data/data/server_config.json` points at our own wire-pod. Use `just connections` to verify what he talks to.
- Back up before editing robot config (`cp -n file file.lan-backup`), and say how to undo.
- `/run/fault_code` is a **FIFO**. Never `cat` it, or the shell hangs.
- BusyBox userland: limited `ls`, `stat` etc. Prefer simple commands.
- Ask the owner before anything that resets onboarding, reboots him unexpectedly, or flashes firmware.
- **Tailscale on the robot** runs from three small units on `/` (`vector-tailscaled`, `vector-hosts`, `vector-tailnet-fw`), installed by `just ts-install-boot`; it also adds `tailscale` to ConnMan's interface blacklist. An OTA removes them all, and restores the shared SSH key: after any OTA, re-run `just ts-install-boot`, `just ssh-key-install` and `just logs-persist`.
- **His system log survives reboots** (since 2026-11-24): `vector-journal` binds `/data/journal` over `/var/log/journal` (a tmpfs), 16 MB per boot, newest 10 boots. Read the last boot with `just logs-prev`, or `journalctl -D /var/log/journal ...` on the robot. Plain `journalctl -b -1` misses it: his machine-id changes every boot, so each boot gets its own folder. The last second or two of a shutdown isn't kept (the log goes back to RAM before `/data` unmounts).
- WireOS has its own firewall (`iptables.service`, default DROP, output only on `wlan0`/`lo`/`tether`). Anything new that must send on another interface needs an exception tied to `iptables.service`, like `vector-tailnet-fw`.
- Set `VECTOR_HOST` to his tailnet name so robot recipes work on any network; `Vector.local` (mDNS) only works on the same LAN.

## wire-pod and the LLM

- **Current setup: wire-pod on an always-on server, tailnet only** ([docs/06](docs/06-session-plan-llm-over-tailscale.md)): `wire-pod/server/` (Quadlet unit, nftables rule, AppArmor profile, `run-chipper.sh`), installed by `just server-install`. Set `WIREPOD_SYSTEMD=true` there so `wirepod-*` recipes use systemctl. `wire-pod/run.sh` is the older desktop/LAN setup (rootful Podman, host networking).
- wire-pod needs ports 80 and 443; its web UI port is `WIREPOD_WEB_PORT` (8080 often clashes).
- Known image quirks (all handled by `just server-install`, see docs/06): settings lost on restart (fixed by `run-chipper.sh`), an empty `apiConfig.json` that blocks first-time setup (seeded with `{}`; this was behind the old "restart once" trick), "forbidden host" at the tailnet name (`WIREPOD_ALLOWED_HOSTS`), SIGTERM ignored as PID 1 (`--init`). The desktop `run.sh` container still needs the restarts that `just wirepod-init` does.
- wire-pod has **no authentication**. Never expose it publicly (no Tailscale Funnel, no port forwarding). Tailnet only.
- The LLM is any OpenAI-compatible endpoint (`just wirepod-ai <model> <endpoint>`). Prefer open-licence, non-thinking models. Current: Qwen3-4B-Instruct-2507 on llama.cpp (`just llm-install`); the first version used Qwen2.5 7B via Ollama. Test a model on wire-pod's real prompt with `just llm-eval` before switching.
- wire-pod's built-in Bluetooth sign-in hangs, or crashes `vic-switchboard` (fault 913), on WireOS 3.0.2: sign robots in with the browser page.

## Legal

Vector's code, animations and sounds belong to Digital Dream Labs and are licensed for use with Vector robots only. Don't copy DDL or WireOS code/assets into this repo, or into designs for other robots.
