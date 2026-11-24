# 2. Multiple Wi-Fi networks

Goal: let Vector join more than one known network (for example home and a second location) without re-running web setup.

Status: **done** (2026-11-22). He keeps every network he's been given (four saved, including a phone hotspot for the away-from-home test) and connects to whichever is around. Adding one: `just wifi-add`; listing: `just wifi-list`.

## Background

- Vector's networking uses **ConnMan** with **wpa_supplicant** underneath. WireOS keeps older versions of both.
- Web setup and BLE setup set **one** network per run. Each run *adds* it to the saved list: the robot had three saved networks from different setups (see Findings).
- ConnMan can remember several networks and joins whichever saved network is in range. That should let us add extras by hand.
- **No WPA3/SAE**: WireOS can see SAE networks but can't join them. Use WPA2, or WPA2/WPA3 mixed mode.

## Plan

1. Look at how the current network is stored (read-only):
   - `connmanctl services`: networks seen, `*A` = autoconnect, `*O` = online
   - `connmanctl config <service> --help` and the service list
   - ConnMan's storage directory is **`/data/lib/connman`**, one `wifi_<id>_managed_psk` folder per saved network (confirmed 2026-11-22). It's on `/data`, so saved networks survive reboots and OTAs; they go only if removed (`connmanctl config <service> --remove`) or `/data` is wiped.
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

### 2026-11-24: each network is listed twice

- `connmanctl services` lists every network once per Wi-Fi interface: `wlan0` (his real Wi-Fi) and `p2p0` (Wi-Fi Direct, switched off). The ids differ only in the interface MAC (`wifi_<mac>_<ssid-hex>_managed_psk`); the `p2p0` one has a `02:` locally-administered MAC.
- Connecting to the `p2p0` id fails with `Error = connect-failed`, whatever the password. Use the id with `wlan0`'s MAC (`cat /sys/class/net/wlan0/address`). `just wifi-add "<part of name>"` now shows only those.
