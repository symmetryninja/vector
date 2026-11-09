# 1. Security check

Goal: confirm the robot is running only what WireOS ships, and close the obvious holes that come with an unlocked bot.

Status: **not started**

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
5. To confirm on the robot: whether an OTA update restores the shared key. If it does, repeat after each update.

## Findings

_Record results here (no IPs, MACs or serials; this repo will be public)._
