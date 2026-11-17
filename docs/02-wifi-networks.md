# 2. Multiple Wi-Fi networks

Goal: let Vector join more than one known network (for example home and a second location) without re-running web setup.

Status: **not started**. Saved networks already persist (three found). Adding one: `just wifi-add`.

## Background

- Vector's networking uses **ConnMan** with **wpa_supplicant** underneath. WireOS keeps older versions of both.
- Web setup and BLE setup set **one** network per run. Each run *adds* it to the saved list: the robot had three saved networks from different setups (see Findings).
- ConnMan can remember several networks and joins whichever saved network is in range. That should let us add extras by hand.
- **No WPA3/SAE**: WireOS can see SAE networks but can't join them. Use WPA2, or WPA2/WPA3 mixed mode.

## Plan

1. Look at how the current network is stored (read-only):
   - `connmanctl services`: networks seen, `*A` = autoconnect, `*O` = online
   - `connmanctl config <service> --help` and the service list
   - Find ConnMan's storage directory. To confirm on the robot: likely under `/data/lib/connman` or `/var/lib/connman`, with one folder per saved network.
2. Add a second network one of two ways:
   - **Interactive:** `connmanctl` → `agent on` → `scan wifi` → `services` → `connect <service>`. ConnMan saves it and should autoconnect later.
   - **Provisioning file:** a ConnMan `.config` file in its storage directory, one `[service_*]` section per network:
     ```ini
     [service_home]
     Type = wifi
     Name = <SSID>
     Passphrase = <password>

     [service_second]
     Type = wifi
     Name = <SSID>
     Passphrase = <password>
     ```
3. Check that it **survives a reboot** and that the bot moves between networks when one goes away.
4. Check what an **OTA update** does to saved networks.

## Keep credentials out of git

SSIDs and passwords must **never** be committed. If we script this, the script reads them from `local/wifi.env` (gitignored), e.g.:

```sh
# local/wifi.env  (NOT committed)
WIFI_1_SSID=...
WIFI_1_PASS=...
```

A `wifi.env.example` with placeholder values can live in the repo.

## Findings

### 2026-11-09: first look (read-only)

- ConnMan's saved networks live in **`/data/lib/connman/`**, one `wifi_<mac>_<hex-ssid>_managed_psk/` folder per network. `/data` is the writable user partition; the root filesystem is read-only.
- The bot already had **three saved networks**, two of them dating from 2021. So saved networks survive OTA updates and the unlock, and web setup **adds** a network rather than replacing the old ones.
- `connmanctl` is installed, so adding another network is a quick `connmanctl` session while that network is in range.
