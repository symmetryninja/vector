# Docs

| # | Topic | Status |
|---|---|---|
| 1 | [Security check](01-security-check.md): confirm the bot is clean, replace the shared SSH key | in progress |
| 2 | [Multiple Wi-Fi networks](02-wifi-networks.md) | not started |
| 3 | [Voice and AI conversation](03-voice-and-ai.md): wire-pod and a local LLM | working (temporary host) |
| 4 | [Flashing and deploying without the website](04-flashing-and-deploying.md) | not started |
| 5 | [Tailscale](05-tailscale.md): voice on any network | experiment working, not permanent |

**Name on the network:** Vector already advertises himself as `Vector.local` (mDNS), so `ssh root@Vector.local` works without looking up his IP. If there are ever two Vectors on one network, the names will clash.

The running log of what was done, and when, is in [../HISTORY.md](../HISTORY.md).
