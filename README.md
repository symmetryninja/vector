# Vector

Notes, config and scripts for an Anki Vector robot running WireOS (community firmware).

- [docs/](docs/README.md): goals and how-tos (security, Wi-Fi, voice/AI, flashing and deploying)
- [HISTORY.md](HISTORY.md): dated log of what has been done

## Setup so far

- Unlocked with the community unlock-prod OTA from https://unlock-prod.skittle.dev/
- WireOS installed from https://websetup.skittle.dev (Custom Firmware stack)

## Useful upstream projects

- [os-vector/wire-os](https://github.com/os-vector/wire-os): WireOS firmware source
- [os-vector/wire-os-victor](https://github.com/os-vector/wire-os-victor): the robot software (`/anki`), buildable and deployable on its own
- [kercre123/wire-pod](https://github.com/kercre123/wire-pod): self-hosted replacement for Anki's cloud (voice, AI, weather)
- [kercre123/wirepod-vector-python-sdk](https://github.com/kercre123/wirepod-vector-python-sdk): Python SDK

## Private information

This repo is meant to be public. Keys, passwords, SSIDs, IPs, serials and API keys never go in it.
Put them in `local/` (gitignored) or environment variables.
