# 5. Tailscale (voice on any network)

Goal: Vector reaches our own wire-pod from any Wi-Fi network, without exposing wire-pod to the internet.

Status: **not started**

## Feasibility (2026-11-09, read-only look)

| Need | On the robot | OK? |
|---|---|---|
| CPU arch | `armv7l` (32-bit ARM, hardfp) | Tailscale publishes static `arm` Linux builds |
| Kernel TUN | `CONFIG_TUN=y`, `/dev/net/tun` present | yes, kernel mode works (no userspace-networking needed) |
| Storage | `/data` has ~670 MB free | yes, the binaries are ~30–40 MB |
| RAM | ~474 MB total, ~220 MB available | probably OK, but watch it: `tailscaled` uses tens of MB |
| Starting at boot | `/` is read-only and OTAs replace it | **to solve**: needs a boot hook that lives in `/data` |

## Plan

1. Download the static `arm` build to `/data/tailscale/` and check its checksum.
2. Run `tailscaled` with its state in `/data/tailscale/` and join with a **pre-auth key, tagged** (e.g. `tag:vector`), non-expiring. The key is a secret: it goes in `local/`, never in git.
3. **Tailnet ACLs:** Vector may only reach the wire-pod host. Nothing on the tailnet may reach Vector except SSH from our own machines. This matters because every unlocked bot shares the same SSH key (see [01](01-security-check.md)), so replace that key first.
4. Point the voice server at wire-pod's tailnet address/MagicDNS name.
5. Find a boot hook that survives OTAs (check what `/data/wired/mods` is; otherwise re-apply a unit after each update).
6. Check the effect on battery, temperature and CPU.

## Notes

- Tailscale's coordination server (run by Tailscale Inc.) sets up the connections but **can't see the traffic**: it's end-to-end encrypted WireGuard. For full self-hosting, Headscale can replace the coordination server.
- If Vector only ever uses networks at places where a wire-pod also runs, Tailscale isn't needed.
