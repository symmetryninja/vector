# 5. Tailscale (voice on any network)

Goal: Vector reaches our own wire-pod from any Wi-Fi network, without exposing wire-pod to the internet.

Status: **experiment working (2026-11-09); not yet permanent**

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

## 2026-11-09 experiment: it works

Voice commands work over the tailnet, with wire-pod reached **by name** using a **real Let's Encrypt certificate**.

What was done (all temporary or backed up; `<host>.<tailnet>.ts.net` = the wire-pod host's MagicDNS name):

1. **Tailscale on the robot:** official static `arm` build (1.104.5, checksum checked against pkgs.tailscale.com), copied to `/data/tailscale/`. Started as a **transient** unit, so a reboot stops it:
   ```sh
   systemd-run --unit=tailscaled-test --property=MemoryMax=96M \
     --setenv=GOMEMLIMIT=48MiB --setenv=GOGC=50 \
     /data/tailscale/tailscaled --state=/data/tailscale/tailscaled.state \
     --statedir=/data/tailscale --socket=/run/tailscale/tailscaled.sock --tun=tailscale0
   /data/tailscale/tailscale --socket=/run/tailscale/tailscaled.sock up \
     --hostname=vector --netfilter-mode=off --accept-dns=false --accept-routes=false
   ```
   `up` prints a login URL, which we approved in the browser, so no auth key was needed. `netfilter-mode=off` and `accept-dns=false` leave the robot's firewall and DNS alone.
   - Cost: `tailscaled` ~25–28 MB RSS. The robot still had ~190 MB available and normal load.
   - Path: direct (LAN) when at home, ~19 ms.
2. **First try, pointing the robot at wire-pod's tailnet IP: failed.** `vic-cloud` verifies TLS properly: `x509: certificate is valid for <LAN IP>, not <tailnet IP>`, and the robot showed the no-connection cloud. wire-pod's self-signed cert only lists the LAN IP it found at setup.
3. **Fix: use the MagicDNS name and a Tailscale certificate.**
   - On the wire-pod host: `tailscale cert --cert-file <vol>/certs/cert.crt --key-file <vol>/certs/cert.key <host>.<tailnet>.ts.net`, where `<vol>` is the `wire-pod-data` volume (the old self-signed pair is kept as `*.selfsigned-lan`). Restart wire-pod. Needs HTTPS certificates enabled for the tailnet.
   - On the robot: append the Let's Encrypt chain to `/data/data/wirepod-cert.crt` (backup: `.lan-backup`). `vic-cloud` trusts its bundled root list **plus** that file.
   - The robot's DNS goes ConnMan → public resolvers, which can't resolve `.ts.net`. For the experiment the name is added through a **runtime bind-mount over `/etc/hosts`** (`mount --bind /data/tailscale/hosts /etc/hosts`). The root fs stays read-only and a reboot undoes it.
   - `/data/data/server_config.json` → `<host>.<tailnet>.ts.net:443` (backup: `server_config.json.lan-backup`).
4. Restart the robot software **as a group**: `systemctl restart anki-robot.target`. Restarting `vic-cloud` alone leaves it endlessly retrying `/dev/socket/_switchboard_gateway_server_`, and restarting `vic-switchboard` too doesn't fix it.

Result: "what time is it" → transcribed and answered by wire-pod over the tailnet.

### Caveats before making it permanent

- **A reboot breaks voice right now:** the config file (on `/data`) points at the name, but Tailscale and the hosts entry are gone after a reboot. Either make both start at boot, or restore the `.lan-backup` files.
- **Boot persistence** needs a hook on `/data`, since `/` is read-only and OTAs replace it. Open question: is there a WireOS-supported startup hook (e.g. under `/data/wired/mods`)?
- **Name resolution** permanently: a hosts entry re-applied at boot (simple; tailnet IPs are stable per node), or `--accept-dns` with ConnMan (messier).
- **Certificate renewal:** Tailscale/Let's Encrypt certs last ~90 days. wire-pod needs `tailscale cert` re-run and a restart before expiry (cron/systemd timer on the host). The robot only trusts the chain, so it doesn't need updating unless Let's Encrypt changes its roots.
- **Being on the tailnet means relying on the tailnet** even at home. Voice now needs Tailscale running on both ends (it still takes the direct LAN path).
- **Tailnet ACLs:** with "allow all", every tailnet device can reach the robot's SSH (shared key!) and its `:8080`/`:8888` pages. Add a `tag:vector` ACL and replace the SSH key before making this permanent.

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
