# Docs

| # | Topic | Status |
|---|---|---|
| 1 | [Security check](01-security-check.md): what leaves the house, auto-updates, SSH key | in progress: audio stays on our devices, auto-updates off, own SSH key |
| 2 | [Multiple Wi-Fi networks](02-wifi-networks.md) | not started (already remembers several; `just wifi-add`) |
| 3 | [Voice and AI conversation](03-voice-and-ai.md): wire-pod and a local LLM | works; on the home server since 2026-11-21 (Qwen3-4B) |
| 4 | [Flashing and deploying without the website](04-flashing-and-deploying.md) | commands ready, not yet used |
| 5 | [Tailscale](05-tailscale.md): voice on any network | permanent since 2026-11-21 (see 06) |
| 6 | [Voice and LLM over Tailscale, permanently](06-session-plan-llm-over-tailscale.md) | done: works at home, after reboots and away from home |
| 7 | [MCP tools for the voice assistant](07-mcp-tools-for-voice.md): Home Assistant first | backlog: approach chosen (MCP proxy), not started |

**Name on the network:** once he's on the tailnet, set `VECTOR_HOST` in `local/.env` to his tailnet name (`vector.<tailnet>.ts.net`): the robot recipes then work on any network. On the same LAN he also answers to `Vector.local` (mDNS). If mDNS fails, set `VECTOR_HOST` to his IP. Two Vectors on one network would clash.

Commands for all of this are in the [justfile](../justfile) (`just` lists them). The running log of what was done, and when, is in [../HISTORY.md](../HISTORY.md).
