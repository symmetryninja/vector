# Docs

| # | Topic | Status |
|---|---|---|
| 1 | [Security check](01-security-check.md): what leaves the house, auto-updates, SSH key | in progress: audio stays home, auto-updates off; SSH key still shared |
| 2 | [Multiple Wi-Fi networks](02-wifi-networks.md) | not started (already remembers several; `just wifi-add`) |
| 3 | [Voice and AI conversation](03-voice-and-ai.md): wire-pod and a local LLM | works; on the home server since 2026-11-21 (Qwen3-4B) |
| 4 | [Flashing and deploying without the website](04-flashing-and-deploying.md) | commands ready, not yet used |
| 5 | [Tailscale](05-tailscale.md): voice on any network | experiment worked; reverted to LAN |
| 6 | [Voice and LLM over Tailscale, permanently](06-session-plan-llm-over-tailscale.md) | in progress: server side done, robot side next |

**Name on the network:** Vector advertises himself as `Vector.local` (mDNS), so `just ssh` works without looking up his IP. If mDNS fails, set `VECTOR_HOST` in `local/.env`. Two Vectors on one network would clash.

Commands for all of this are in the [justfile](../justfile) (`just` lists them). The running log of what was done, and when, is in [../HISTORY.md](../HISTORY.md).
