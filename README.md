# Vector

Notes, scripts and a `justfile` for running an **Anki Vector** robot on **WireOS** (community firmware) with a **self-hosted voice server and a local open LLM**. Nothing he hears leaves the house.

## Where things stand

| Area | State |
|---|---|
| Firmware | Unlocked prod bot running WireOS 3.0.x. Auto-updates **off**. |
| Privacy | Voice goes only to our own wire-pod. The WireOS community cloud is not used. |
| Voice | [wire-pod](https://github.com/kercre123/wire-pod) in a container, local Vosk speech-to-text. |
| Conversation | Local open model (Qwen2.5 7B, Apache-2.0) via Ollama, wired into wire-pod's intent graph. |
| Hosting | Temporary desktop host, **currently stopped** (`just up` to start). Moving to the home model server. |
| Tailscale | Proven to work (voice over the tailnet with a real cert), reverted to LAN for now. Permanent setup planned: [docs/06](docs/06-session-plan-llm-over-tailscale.md). |
| To do | Replace the shared SSH key, router rule, weather provider, face enrolment, Bluetooth pairing without third-party sites. |

## Quick start

Needs: [`just`](https://github.com/casey/just), `ssh`, Podman (or Docker), Ollama, and an unlocked Vector on WireOS that you can SSH into.

```bash
cp env.example local/.env     # then edit: Vector's address, SSH key path, ports, model
just                          # list all commands
just find                     # find Vector on the network
just status                   # services, connections, memory on Vector
just up                       # start Ollama + wire-pod
```

First-time wire-pod setup, in order:
1. `just wirepod-run`: create the container
2. `just wirepod-init`: speech language, IP mode, plus the restarts the image's bugs need
3. `just wirepod-setup-bot`: point Vector at it, then sign him in over Bluetooth
4. `just wirepod-ai`: connect the LLM

The details and pitfalls are in [docs/03](docs/03-voice-and-ai.md).

## What's here

- [docs/](docs/README.md): one doc per goal, with findings and status:
  1. [Security check](docs/01-security-check.md): what leaves the house, auto-updates, SSH key
  2. [Multiple Wi-Fi networks](docs/02-wifi-networks.md)
  3. [Voice and AI conversation](docs/03-voice-and-ai.md): wire-pod, local LLM, reboot recovery
  4. [Flashing and deploying without the website](docs/04-flashing-and-deploying.md)
  5. [Tailscale](docs/05-tailscale.md): the experiment, and why not Funnel
  6. [Planned session: voice and LLM over Tailscale, permanently](docs/06-session-plan-llm-over-tailscale.md)
- [justfile](justfile): commands for all of the above, grouped (`stack`, `robot`, `privacy`, `wifi`, `flash`, `wire-pod`, `ollama`, `tailscale`).
- [wire-pod/run.sh](wire-pod/run.sh): creates the wire-pod container (rootful Podman, host networking).
- [env.example](env.example): every setting the `justfile` reads.
- [HISTORY.md](HISTORY.md): dated, plain-language log of what was done.
- [CLAUDE.md](CLAUDE.md): conventions and safety rules for working on this repo (and the robot) with Claude Code.

## Useful upstream projects

- [os-vector/wire-os](https://github.com/os-vector/wire-os): WireOS firmware
- [os-vector/wire-os-victor](https://github.com/os-vector/wire-os-victor): the robot software (`/anki`), buildable and deployable on its own
- [os-vector/vector-docs](https://os-vector.github.io/vector-docs): community docs
- [kercre123/wire-pod](https://github.com/kercre123/wire-pod): self-hosted replacement for Anki's cloud (voice, AI, weather)
- [kercre123/wirepod-vector-python-sdk](https://github.com/kercre123/wirepod-vector-python-sdk): Python SDK

How the bot was unlocked: community unlock-prod OTA via [unlock-prod.skittle.dev](https://unlock-prod.skittle.dev/), then WireOS from websetup.skittle.dev (Custom Firmware stack). Both were checked before use (see HISTORY, 2026-10-27).

## Private information

This repo is public-ready: **no keys, passwords, Wi-Fi names, IPs, serials, tailnet names or API keys** are in it or its history. Put them in `local/` (gitignored) or environment variables.

## Legal

Vector, Anki and the robot's software and assets belong to Digital Dream Labs. Their published code and animations are licensed for use **with Vector robots only**. This repo contains only our own notes and scripts, no DDL code or assets. Not affiliated with Digital Dream Labs or the WireOS/wire-pod projects.
