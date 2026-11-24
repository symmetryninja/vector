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
- 16:00–16:30: Set up wire-pod, our own voice server, in a container on the desktop. Speech recognition runs locally. Pointed Vector at it, turned his voice service back on, and signed him in over Bluetooth. The first sign-in failed because wire-pod's voice port hadn't started after a restart; a second restart fixed it. He now answers voice commands, and everything he hears stays in the house.
- He can't do weather yet (no weather provider set up) and couldn't learn my face. He kept losing sight of it during enrolment, and once thought I was someone else.
- 16:45: Gave Vector a brain. wire-pod now passes anything he doesn't recognise as a command to an open model (Qwen2.5 7B) running locally on the desktop's GPU through Ollama. He holds a conversation, answers in well under a second once warmed up, and it all stays in the house. This is a stand-in until the models move to the home AI server.
- 17:00: Looked at whether Tailscale Funnel could safely expose wire-pod to the internet. Decided against it: wire-pod has no login, and its web UI can drive the robot and show his camera. Better to put Vector on the tailnet itself. Notes in the Tailscale doc.
- 17:35–17:55: Tailscale experiment. Put Vector on the tailnet (approved in the browser). Pointing him at the desktop's tailnet address first failed because wire-pod's certificate only covered its home-network address. Switched to the desktop's Tailscale name with a proper Let's Encrypt certificate from Tailscale, and he answered "what time is it" over the tailnet. Tailscale costs him about 25 MB of memory. It's all temporary for now: a reboot of Vector would undo the Tailscale side but leave his config pointing at the tailnet name.
- 18:00: Rolled the Tailscale experiment back so a reboot can't leave Vector voiceless. He's back on the home network setup and Tailscale is stopped on him. Decided the permanent version will be built on the machine that will run the AI models, once that's ready, with wire-pod moving there too.

## 2026-11-12

- Stopped wire-pod on the desktop (Vector has no voice until it's started again; Ollama is still running).
- Added a `justfile` with commands for everything so far: robot status/logs/SSH, cloud voice off/on, auto-update, Wi-Fi, flashing without the website, wire-pod (start/stop/first-time setup/bot setup/AI), Ollama, and the Tailscale experiment. Private settings come from a gitignored `local/.env`.
- While testing it, found that another container on the desktop now uses port 8080, which wire-pod's web UI needs. wire-pod's UI port is now configurable. Vector wasn't reachable on the network at the time, so the robot commands were only checked as far as connecting.

## 2026-11-18

- Checked whether Vector's Tailscale is persistent: it isn't. It's installed on him but not running or starting at boot, and he shows offline in the tailnet (his node key expires May 2027). His voice doesn't depend on it.
- Fixed a bug in `just ssh` where part of a command could run on the desktop instead of on Vector.
- Wrote up the permanent "voice and LLM over Tailscale" setup as a planned session (doc 06), to run once the model server's container migration is done.
- Refreshed the README and every doc status to match reality, and added a CLAUDE.md so anyone using Claude Code with this repo gets the safety rules and conventions up front.
- Looked into reusing Vector's animations on a self-built robot: Digital Dream Labs' licence only allows them on real Vectors, so a custom robot needs its own animations.

## 2026-11-21

- Moved Vector's brain to the always-on home server. wire-pod (his voice server) now runs there as a system service, and only devices on the tailnet can reach it; the home network can't, because wire-pod has no login.
- Gave him a small language model of his own (Qwen3-4B-Instruct-2507) instead of sharing the server's big one, so he never waits behind other jobs. Picked it by testing two small models on wire-pod's real prompt: the newer, smaller one made fewer mistakes with Vector's animation commands and was just as fast. The test script is in the repo, so anyone can check their own model.
- Found and worked around two bugs in wire-pod's container image: it forgot its settings on every restart, and its first-time setup could never finish. The second is probably what was behind the "restart once" trick from 2026-11-09.
- New `just` recipes to install all of this on a server.
- Replaced the SSH key that every unlocked Vector shares with our own. The shared key no longer gets in.
- Made Tailscale start on Vector at every boot. WireOS has no supported way to run things from his data partition at boot, so two tiny services on his system partition start it; they need re-adding after a firmware update (auto-updates are off).
- Pointed Vector at the new server by its tailnet name, with a proper certificate, without ever opening wire-pod to the home network.
- First reboot after that: he got stuck on his loading screen. The service that teaches him the server's name ran before his encrypted data partition was readable and quietly skipped itself. Fixed by making it wait; he now comes back by himself.
- Tried signing him in using the server's own Bluetooth, so no outside website is involved. Pairing works, but wire-pod's page hangs, and a cut-down version crashed his Bluetooth service (fault 913). Signed him in with the usual browser page instead, which worked. Notes for a future attempt are in doc 06.
- Voice and conversation work over the tailnet, and again after a reboot with nothing done by hand.

## 2026-11-22

- Set up tailnet access rules: Vector is tagged and can only reach wire-pod on the server. Two gotchas worth knowing: the default "everyone" rule also covers tagged devices, so it has to become "members" for the tag to mean anything; and its destination must stay "all devices", or your own machines lose access to Vector.
- He remembers four Wi-Fi networks now, including the phone hotspot, ready for the away-from-home test.
- Away-from-home test: moved Vector to the phone's hotspot with the phone on mobile data. Tailscale reconnected on its own and found a direct path over the mobile network. "What time is it" and a question for the model both worked with no noticeable delay. Vector now works from anywhere with Wi-Fi, and nothing is open to the internet.
- After coming home from the hotspot, his voice stopped working. His network manager had crashed while switching Wi-Fi, and on restart it switched Tailscale's network interface off and re-applied WireOS's firewall, which only lets traffic out over Wi-Fi. Fixed both: the network manager now leaves Tailscale alone, and the firewall lets his Tailscale traffic out (re-added automatically whenever the firewall reloads). Tested by restarting the network manager and reloading the firewall on purpose: the tailnet stayed up.

## 2026-11-24

- Planned (not started) letting Vector's voice assistant use tools, starting with Home Assistant, so he can answer things like "are the workshop lights off?". wire-pod can't do tool calls itself, so the plan is a small go-between service next to his model. Parked in the backlog as doc 07, with notes on recognising who's speaking.
- Added a network for Vector at a new location. Adding it the usual way kept failing (his network manager gave up before asking for the password, and the network list shows every network twice, one copy unusable), so there's now a recipe that saves a network with its password in one step. After switching to it, the tailnet couldn't reach him until a restart; the cause wasn't found because his logs don't survive a reboot. Noted what to check if it happens again.
- Made Vector keep his system log across restarts (on his data partition, capped in size), so the next time something breaks and a restart fixes it, the evidence is still there. Like the Tailscale setup, it needs re-adding after a firmware update. Tested with a reboot: the previous boot's log was there afterwards.
