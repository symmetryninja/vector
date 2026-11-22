# 1. Security check

Goal: confirm the robot is running only what WireOS ships, and close the obvious holes that come with an unlocked bot.

Status: **in progress**: no audio leaves our own devices (voice goes to our own wire-pod, over the tailnet), auto-updates off, and the shared SSH key is replaced by our own (2026-11-21, `just ssh-key-install`; see [06](06-session-plan-llm-over-tailscale.md)). Still to do: router rule, full checklist.

## Known risks of an unlocked WireOS bot

| Risk | Why | Fix |
|---|---|---|
| Shared SSH root key | Every unlocked Vector accepts the same public `ssh_root_key`. Anyone on the same network who has it gets root. | Add your own key, then remove the shared one (see below). |
| Unauthenticated web servers | WireOS runs a settings server on `:8080` (wake word, CPU profile, auto-update opt-out) and a demo page on `:8888`. Assume anyone on the LAN can use them. | Keep the bot on a trusted network. Consider a guest/IoT VLAN. |
| Firmware over plain HTTP | OTAs come from `http://ota.pvic.xyz/...` and the web setup's `:8000` server, unencrypted. | Flash only on a trusted network. Optionally download the OTA, check its hash, and serve it locally (see [04](04-flashing-and-deploying.md)). |
| Auto-updates | The bot can pull new WireOS builds automatically. | Decide whether you want this. You can opt out in the `:8080` settings page. |
| No WPA3 | WireOS's Wi-Fi stack can't connect to SAE/WPA3 networks. | Use WPA2 (or WPA2/WPA3 mixed mode). |

## Checklist

All read-only unless noted. Run over SSH (`ssh -i <key> root@<vector-ip>`; older keys may need `-o PubkeyAcceptedAlgorithms=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa`).

### Who can log in
- [ ] `cat /root/.ssh/authorized_keys` (and any other `authorized_keys` on the system): only expected keys present
- [ ] `cat /etc/passwd /etc/shadow`: no unexpected accounts or passwords
- [ ] `ss -tlnp` (or `netstat -tlnp`): list every listening port and the process behind it

### What runs
- [ ] `systemctl list-units --type=service --state=running`
- [ ] `systemctl list-unit-files --state=enabled`
- [ ] `ps aux`: nothing unexpected
- [ ] `crontab -l`, `ls /etc/cron* /var/spool/cron* 2>/dev/null`
- [ ] Look for recently changed binaries/scripts outside the OTA: `find / -xdev -newer /etc/os-release -type f 2>/dev/null | grep -v -E '^/(proc|sys|data/data)'`

### What it talks to
- [ ] `ss -tnp` while idle, again while using voice: note every remote address
- [ ] Better: watch the bot's traffic from the router/firewall for a day. The robot can't hide traffic from the router the way it could hide from commands run on it.
- [ ] Expected destinations: your voice server (wire-pod, if used), the OTA server, NTP/DNS. Anything else needs explaining.

### Camera and mic
- [ ] Check which processes have the camera/mic devices open: `ls -l /proc/*/fd 2>/dev/null | grep -E 'video|snd'`

## Replace the shared SSH key

1. On your PC: `ssh-keygen -t ed25519 -f ~/.ssh/vector_ed25519` (keep it **out of this repo**).
2. Copy the public key to the bot and add it to `/root/.ssh/authorized_keys`. The root filesystem may be read-only; WireOS has `mrw` (= `mount -o rw,remount /`).
3. Check you can log in with the new key **before** removing anything.
4. Remove the shared key's line from `authorized_keys`.
5. ✅ Done 2026-11-21 with `just ssh-key-install` (checks with `just ssh-key-check`). The key file is `/etc/ssh/authorized_keys` on the read-only root, which an OTA replaces, so an OTA brings the shared key back: re-run it after each update.

## Findings

_Record results here (no IPs, MACs or serials; this repo will be public)._

### 2026-11-09: what talks to the internet (read-only look)

Priority: **the microphone must not send anything to a service we don't control.**

| What | Where it goes | Audio? | Notes |
|---|---|---|---|
| `vic-cloud` (voice, settings, tokens) | `vicapi.pvic.xyz:8081`, community-hosted | **yes**, everything after the wake word | Holds open connections to it all the time. Currently answers voice with errors anyway. |
| `update-engine` (hourly timer) | `ota.pvic.xyz` | no | Auto-updates. New firmware can change anything, including this table. |
| DNS (ConnMan) | `8.8.8.8` / `8.8.4.4` (Google) | no | Leaks which hosts he looks up. |
| Alexa (AVS libraries) | Amazon | would be | Libraries are present and a `wasOptedIn` marker exists. To confirm: whether Alexa is actually active. |

- The wake word ("Hey Vector") is detected **on the robot** (Picovoice). Audio is only streamed after it fires, so the voice server is what matters.
- Firewall: `iptables` is installed and an `iptables.service` is enabled, with a default-deny ruleset in `/etc/iptables/iptables.rules`. But the **live** policy is ACCEPT for everything, so nothing is blocked right now.
- `/` is read-only and OTAs replace it. Anything we change there (units, firewall rules) can be undone by an update. Persistent changes belong in `/data`, or **outside the robot** (router/firewall), where an update can't touch them.

Plan:
1. ✅ **Stop `vic-cloud`** (2026-11-09). Masked so it can't start at boot. Verified across a reboot: no internet connections remain, and the rest of the robot runs normally.
2. **Belt and braces:** a router rule that lets the robot talk only to the LAN (plus the tailnet if used, see [05](05-tailscale.md)).
3. ✅ **Point `vic-cloud` at our own wire-pod and re-enable it** (2026-11-09, [03](03-voice-and-ai.md)). `vic-cloud` is unmasked again. Its config in `/data/data/server_config.json` sends voice only to wire-pod; the community server was never contacted (0 hits on a temporary block).
4. ✅ **Auto-updates off** (2026-11-09). Set through WireOS's own switch (`:8080` page → `/api/mods/AutoUpdate/setInhibited`), which writes `/data/data/user-do-not-auto-update`. Verified across a reboot.

How it was done, and how to undo it:

```sh
# disable the voice/cloud service (root fs is read-only, so remount briefly)
mount -o rw,remount / && systemctl stop vic-cloud && systemctl mask vic-cloud; mount -o ro,remount /
# undo
mount -o rw,remount / && systemctl unmask vic-cloud; mount -o ro,remount /; systemctl start vic-cloud

# auto-updates: off / on
curl http://Vector.local:8080/api/mods/AutoUpdate/setInhibited
curl http://Vector.local:8080/api/mods/AutoUpdate/setAllowed
```

Notes:
- `just voice-cloud-off` / `just voice-cloud-on` do the above. `just connections` shows what he's connected to.
- The mask lives on the root filesystem, which an OTA replaces. If firmware is ever updated, check `systemctl is-enabled vic-cloud` afterwards.
- With voice off, "Hey Vector" still triggers (the wake word is on the robot), but commands will fail.
- After the reboot, `systemctl --failed` lists `adbd`, `chgrp-diag`, `ip6tables`, `ldconfig` and `systemd-vconsole-setup`. All except `adbd` also failed on earlier boots. `adbd` (USB debug bridge, localhost only) failed on this boot but had been running before. It's probably unrelated to the change; to check.
