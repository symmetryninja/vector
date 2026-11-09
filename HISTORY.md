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
- Switched this repo's commit email to the GitHub noreply address and rewrote the first two commits to use it.
- 15:26: First look around Vector over SSH (read-only). He was found on the network automatically (mDNS). Findings:
  - Wi-Fi: he already remembers three networks, so multiple networks are supported and survive updates.
  - Voice: WireOS sends speech to a community-hosted server on the internet, which is currently answering with errors. That's why he just shrugs. Fix: run wire-pod at home and point him at it.
- 15:35: Set priorities: first, his microphone must not send anything to an internet service we don't control. Second look (read-only):
  - The voice service keeps a constant connection to the community server, so audio after "Hey Vector" leaves the house. The firewall tools are there, but nothing is being blocked. Auto-updates check hourly, and DNS goes to Google.
  - He already answers to `Vector.local`, so no IP hunting is needed.
  - Tailscale looks possible: his kernel supports it and there's room. The hard part is making it start at boot in a way that survives updates.
- 15:40: Turned off Vector's cloud voice service so nothing he hears goes to the internet, and turned off auto-updates so his firmware only changes when we choose. Rebooted him to check both stay off: they do, and he otherwise behaves normally. He still reacts to "Hey Vector", but can't act on commands until we run our own voice server.
