# CLAUDE.md

Guidance for Claude Code (and humans) working in this repo. It manages a real Anki Vector robot on WireOS, a self-hosted wire-pod voice server, and a local LLM. Read [README.md](README.md) first for the current state.

## Repo conventions

- **Public repo: never commit private data.** No keys, passwords, Wi-Fi names, IPs, MACs, robot serials/ESNs/names, tailnet names or API keys, in files, commit messages or HISTORY. Use placeholders (`<vector-ip>`, `<host>.<tailnet>.ts.net`). Real values live in `local/.env` (gitignored; see `env.example`). Grep the diff for addresses and names before committing.
- **`HISTORY.md`**: add a dated, plain-language entry for every meaningful step (what was done and why, not commands). Newest at the bottom, grouped by date heading.
- **`docs/0N-*.md`**: one doc per goal. Keep each `Status:` line and the table in `docs/README.md` accurate. Record findings with dates under `## Findings`; mark anything unverified as "to confirm".
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

## wire-pod and the LLM

- `wire-pod/run.sh` runs rootful Podman with **host networking**. wire-pod needs ports 80 and 443; its web UI port is `WIREPOD_WEB_PORT` (8080 often clashes).
- Known image quirks: restart once before first-time setup, and again after it, or port 443 isn't listening (`just wirepod-init` handles both).
- wire-pod has **no authentication**. Never expose it publicly (no Tailscale Funnel, no port forwarding). Tailnet only.
- The LLM is any OpenAI-compatible endpoint (`just wirepod-ai <model> <endpoint>`). Prefer open-licence models; this repo documents Qwen2.5 7B via Ollama.

## Legal

Vector's code, animations and sounds belong to Digital Dream Labs and are licensed for use with Vector robots only. Don't copy DDL or WireOS code/assets into this repo, or into designs for other robots.
