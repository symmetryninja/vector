# History

A plain-language, dated log of what has been done with Vector. Newest entries at the bottom.
Technical detail lives in [docs/](docs/README.md). No keys, passwords, network names or addresses here.

---

## 2026-10-27

- Vector is a production bot, so it only accepts signed firmware. Looked into community unlocking.
- Checked the unlock site (unlock-prod.skittle.dev) and the web setup tool it uses (websetup.skittle.dev) before using them. Both look legitimate: the unlock page is just instructions, and web setup is a modified copy of Anki/DDL's open-source Vector Web Setup. Points noted: firmware downloads over plain HTTP, the unlock firmware itself can't be inspected, and every unlocked bot shares one SSH root key.
- Got Chrome on Linux Mint talking to Vector over Web Bluetooth by enabling `chrome://flags/#enable-experimental-web-platform-features`. Pairing then worked.
- Stock prod and escape-pod firmware flashed fine. WireOS failed (cloud icon with an exclamation mark) because the bot wasn't unlocked yet.

## 2026-10-28

- Confirmed the web setup's Utility stack lists the unlock firmware again (it had been pulled for a bug in September, upstream issue os-vector/wire-os#63).

## Between 2026-10-28 and 2026-11-09

- Unlocked Vector with Unlock-Prod and installed WireOS. He boots and works.

## 2026-11-09

- 15:00: Created this repo (local and private on GitHub, to be made public later).
- 15:16: Started the docs with four goals: confirm the bot is secure, add multiple Wi-Fi networks, give him an AI service so he can hold a conversation, and flash/deploy without the website. Researched WireOS, wire-os-victor and wire-pod for each one. Nothing changed on the robot yet.
- Set the rule that nothing private goes in the repo or its history. Private values go in a gitignored `local/` folder.
