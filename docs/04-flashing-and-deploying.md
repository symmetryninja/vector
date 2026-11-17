# 4. Flashing and deploying without the website

Goal: update firmware, and later deploy our own code, from a terminal on this machine instead of web setup in Chrome.

Status: **commands ready, not yet used**: `just flash-url <url>` (method A) and `just flash-file <file.ota>` (serves it locally and prints its checksum).

There are three levels. Each needs less of the website than the one before.

## A. Install a full OTA over SSH (no website at all)

WireOS includes `update-os`. While SSHed into the bot:

```sh
update-os http://ota.pvic.xyz/vic/latest/dev.ota
```

That is the current WireOS dev build for unlocked prod bots. To use a specific or self-built OTA, serve it from this machine and point `update-os` at it:

```sh
# on the PC, in the folder holding the .ota
python3 -m http.server 8000
# on the bot
update-os http://<pc-ip>:8000/<file>.ota
```

Serving it locally also means we can check the OTA's hash before flashing, instead of trusting a plain-HTTP download (see [01](01-security-check.md)).

Planned: a `scripts/flash-ota.sh` that takes an OTA URL or file plus the bot's address, serves the file if needed, runs `update-os` over SSH, and waits for the reboot. The bot's address comes from `local/` or an argument, never hard-coded.

## B. Deploy only the Vector software (`wire-os-victor`)

The upstream path for development. You don't rebuild the whole OS:

- [`wire-os-victor`](https://github.com/os-vector/wire-os-victor) builds just the `/anki` programs (behaviours, animations, the main robot software).
- Build: `./build/build-v.sh` (Docker, Linux x86_64/arm64 or M-series Mac).
- Deploy to a bot already running WireOS: `./build/deploy-v.sh` (asks for / uses the bot's IP).
- There's also a Webots simulator, so many changes can be tested without the robot.

Our own changes would live in a fork of `wire-os-victor`. This repo holds notes and helper scripts, not a copy of that code.

## C. Build the whole OS (`wire-os`)

Only needed for OS-level changes (kernel, system packages). It's heavy: 8–16 GB RAM, 100–200 GB disk, 30 min to 3 h per build, x86_64 recommended (Docker). Output is `_build/3.0.1.<n>.ota`, which you then flash with method A.

## Recovery fallback (when SSH isn't available)

If the bot won't boot properly, it can still be flashed from recovery mode (on the charger, hold the button ~15 s until the back lights go dark blue). This needs Bluetooth:

- Web setup's BLE terminal: `ota-start <url>`
- Or a command-line BLE tool. [`sergioamr/vecsetup`](https://github.com/sergioamr/vecsetup) is one. **Not vetted yet**; review it before using.

## Findings

_Record what worked here._
