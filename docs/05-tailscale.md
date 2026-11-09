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

## Why not Tailscale Funnel (public exposure)?

Funnel publishes a service on the tailnet node to the **whole internet** at `https://<node>.<tailnet>.ts.net` (ports 443, 8443, 10000). It has **no authentication of its own**. Whatever is behind it must protect itself, and wire-pod can't:

- The **web UI (`:8080`)** has no login. From it anyone could change settings, read API config, and use the "control" page: drive the robot, **watch his camera stream** and make him speak.
- The **voice server (`:443`)** accepts robots quite permissively. Strangers could use it as a free speech-to-text + LLM service on our GPU, and voice traffic would be exposed to whatever bugs it has.
- Funnel addresses are published in Certificate Transparency logs, so they get found and scanned quickly.

Ways to secure a Funnel, roughly from weakest to strongest:
1. **Expose only the voice port**, never `:8080`. That's necessary, but it doesn't make it safe.
2. **Put an authenticating proxy in front** (e.g. Caddy/nginx with **mutual TLS**, so only a client certificate we issue gets through). That's the only option that really locks it to Vector, but it depends on Vector's `vic-cloud` presenting that client cert. **To confirm:** whether it can (it does send a robot cert, `/data/etc/robot.pem`, but whether it would work as an mTLS client cert is untested).
3. Rate limiting and logging: they help you notice abuse but don't prevent it.

**Decision: don't use Funnel.** Put Vector *on* the tailnet instead (plan above). Then only our devices can reach wire-pod, Tailscale handles the identity, and nothing is public. Funnel only makes sense for clients that can't run Tailscale. If we ever need that, go with option 2, and treat it as a project of its own.

Middle ground if needed: **node sharing** gives one specific other tailnet (e.g. a family member's) access to the wire-pod node only, still not public.

## Notes

- Tailscale's coordination server (run by Tailscale Inc.) sets up the connections but **can't see the traffic**: it's end-to-end encrypted WireGuard. For full self-hosting, Headscale can replace the coordination server.
- If Vector only ever uses networks at places where a wire-pod also runs, Tailscale isn't needed.
