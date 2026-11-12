# 3. Voice and AI conversation

Goal: talk to Vector properly. He should answer questions and hold a conversation using an AI service we choose, with our own API key.

Status: **working (2026-11-09): local wire-pod plus a local open model via Ollama (temporary test setup)**

## Why he can't talk much right now

Vector does wake-word detection on the robot (WireOS uses Picovoice Porcupine). Everything after "Hey Vector" (speech-to-text, working out what you meant, answering questions) is done by a **voice server**. Anki's cloud is gone, so without a replacement server he understands little or nothing.

## The replacement: wire-pod

[wire-pod](https://github.com/kercre123/wire-pod) is a self-hosted voice server by the same author as WireOS. It runs on a PC, Raspberry Pi (64-bit; arm64 required on a Pi 5), Mac, Windows or Android. From its wiki:

- Every built-in voice command works.
- Speech-to-text runs locally (Vosk by default; Whisper on powerful hardware).
- **Knowledge graph** ("Hey Vector, I have a question"): answered by **OpenAI, Together, Ollama** (local, no API key) or Houndify.
- **Intent graph** (OpenAI or Together only): anything that isn't a known command goes straight to the LLM. This is what makes him conversational.
- Weather via weatherapi.com or openweathermap.org.
- Custom intents (your own voice commands).
- A settings web UI on port **8080** of the wire-pod host. This is a different machine from the robot's own `:8080` WireOS page.
- Keeps the Python SDK working (writes `sdk_config.ini`).

## Plan

1. **Pick a host** for wire-pod: something that's always on, on the same network as Vector.
2. **Install wire-pod** (wiki: Installation, "Other Linux"): `git clone` it, then `sudo STT=vosk ./setup.sh`, then `sudo ./setup.sh daemon-enable` to run it as a service.
3. **Point WireOS at wire-pod.** To confirm: how WireOS finds its voice server. The wire-pod guide is written for stock "escape pod" firmware, which looks for a host called `escapepod.local`, so make sure nothing else on the network uses that name. Check WireOS's `:8080` page and the robot's server config before changing anything.
4. **Authenticate the bot** with wire-pod (its setup page walks through this).
5. **Add the AI provider** in wire-pod's web UI (API setup), and enable the intent graph for free-form conversation.
6. Test, then tune the personality/prompt and add weather.

## Choosing a provider

| Option | Key needed | Conversational (intent graph) | Notes |
|---|---|---|---|
| OpenAI | yes | yes | Easiest. Usage is billed. |
| Together | yes | yes | Hosted open models, often cheaper. |
| Ollama | no | knowledge graph only (per wiki) | Runs locally. Private, but needs a capable machine. |
| Houndify | yes | no | Older option. |

To confirm: whether newer wire-pod versions support more providers or OpenAI-compatible endpoints. If they do, other services could be used.

## Keep keys out of git

API keys are entered in wire-pod's web UI and stored on the wire-pod host, **not** in this repo. If we ever script the setup, keys come from `local/` (gitignored) or environment variables only. Never paste a key into these docs or into `HISTORY.md`.

## Findings

### 2026-11-09: first look (read-only)

- WireOS (3.0.2.0) doesn't look for a local escape pod. Its server config, `/anki/data/assets/cozmo_resources/config/server_config.json`, points voice (`chipper`), settings (`jdocs`) and tokens (`tms`) at a **community-hosted server, `vicapi.pvic.xyz:8081`**. So after the wake word, audio goes to that server over the internet.
- That server is reachable with a valid TLS certificate, but voice requests fail: the log shows `Got cloud error message type error`, then the "I don't know" animation. That's why he can't interact.
- The file is on the read-only root (`/`), and an OTA would overwrite it. To confirm: the supported way to point WireOS at wire-pod (wire-pod's docs have a section for unlocked bots).
- WireOS's own settings page (`:8080`) covers wake word, sensitivity, CPU profile, auto-update, faces and some settings, but has no voice-server or AI option.
- Running wire-pod at home would also keep his microphone audio on the local network (see [01](01-security-check.md)).

### 2026-11-09: wire-pod running (first go, on a desktop)

- wire-pod runs in a **rootful Podman container with host networking** on a desktop PC: [`wire-pod/run.sh`](../wire-pod/run.sh). Host networking is needed so wire-pod advertises the host's LAN address to the robot. Rootful because it binds ports 80 and 443.
- Speech-to-text is **Vosk, English (US), running locally**. Its self-test transcribes a sample in ~0.3 s.
- **Container gotcha:** on the very first start the image creates an empty `apiConfig.json`, so it never picks up `STT_SERVICE=vosk` and refuses to set a language. **Restart the container once** before first-time setup. After first-time setup, restart again, or the voice server on **port 443 isn't started** and the robot gets `connection refused` (the sign-in page then says "unable to communicate with your wire-pod instance").
- First-time setup was done through wire-pod's API instead of the web page: `POST /api/set_stt_info {"language":"en-US"}`, then `GET /api-chipper/use_ip?port=443`. Use **IP mode**, not escape-pod mode, since WireOS doesn't look for `escapepod.local`.
- Pointing the robot at it: wire-pod's **"Set up OSKR/dev bot"** (SSH) step (`POST /api-ssh/setup` with the bot's IP and the SSH key). For WireOS it:
  - writes `/data/data/server_config.json` (voice, settings and tokens → wire-pod host:443) and `/data/data/wirepod-cert.crt`; these are on `/data`, so they survive OTAs
  - regenerates the robot's cert, clears its sign-in token and onboarding state (faces/photos are kept), and restarts the robot software
  - leaves WireOS's own `vic-cloud` in place ("modern CFW detected")
- Then the robot shows its name and `wp.pvic.xyz`. That redirects to `wpsetup.keriganc.com`, the wire-pod author's copy of DDL's BLE setup page. Pair in Chrome and click Activate. The page sends only a dummy `test/test` login to its own server; the real sign-in is between the robot and wire-pod.
- Result: the robot's only connections are to the wire-pod host. Basic voice commands work.
- To be aware of: wire-pod has `DEBUG_LOGGING=true`, so **transcripts of what's said appear in the container log** (on the wire-pod host only).
- When wire-pod moves to another machine: run `run.sh` there, do the first-time setup, re-run the SSH bot setup and sign in again. A fixed address (DHCP reservation) for the wire-pod host avoids breakage when its IP changes.

### 2026-11-09: AI conversation with a local open model

Temporary test setup, until the models move to the home AI server (being containerised).

- **Model:** [Qwen2.5 7B Instruct](https://ollama.com/library/qwen2.5) (`qwen2.5:7b`, ~4.7 GB, **Apache-2.0**), served by **Ollama** on the same desktop as wire-pod.
  - Picked for its open licence, speed (~0.3 s per short answer on a 16 GB GPU once loaded, ~2 s for the first request) and good instruction following.
  - Not Qwen3: it "thinks" out loud by default, and Ollama 0.7.0 can't turn that off, so Vector might read the thinking aloud.
- **wire-pod settings** (Knowledge Graph → **Custom**), or `POST /api/set_kg_api`:

  | Field | Value |
  |---|---|
  | provider | `custom` |
  | endpoint | `http://localhost:11434/v1` (wire-pod uses host networking, so localhost is the host) |
  | key | `ollama` (placeholder; Ollama needs none) |
  | model | `qwen2.5:7b` |
  | intent graph | on: anything that isn't a built-in command goes to the model |
  | LLM actions | on: he animates during answers (needed for conversations) |
  | save chats | on: earlier chats give context. Stored in wire-pod's data volume on the host. |
  | prompt | default ("You are a helpful, animated robot called Vector…") |

- Restart wire-pod after changing these.
- Result: free-form questions are answered by the local model. **Nothing leaves the house.**
- Moving to another model server later: change `endpoint` (and `model`) only.
- Housekeeping: on this desktop Ollama is set to listen on all interfaces (`OLLAMA_HOST=0.0.0.0`, no auth). wire-pod only needs localhost. On the final server, bind it to localhost or restrict it to the wire-pod host.

#### After a reboot of the wire-pod host

Shortcut: `just up` (and `just down`). `just wirepod-status` shows which ports wire-pod holds.

**Port clash:** wire-pod's web UI defaults to 8080. If something else on the host already uses it, wire-pod's UI can't start. Set `WIREPOD_WEB_PORT` (e.g. in `local/.env`) and recreate the container with `just wirepod-run`; settings are kept in the volume. The robot only uses 80 and 443.

Neither service starts at boot on the temporary desktop host (on purpose for now). Until they're running again, Vector hears "Hey Vector" but can't act on anything.

```sh
sudo systemctl start ollama     # the model server
sudo podman start wire-pod      # existing container, keeps all settings
```

Check it's up: `sudo ss -tlnp | grep -E ':(443|8080) '` should show both ports. If 443 is missing, `sudo podman restart wire-pod`.

`podman start` reuses the container. `wire-pod/run.sh` **recreates** it from the latest image. Settings survive either way (they're in the `wire-pod-data` volume), but only use `run.sh` to update or rebuild.

To make both start at boot later: `sudo systemctl enable ollama`, and for the container, `podman generate systemd`/Quadlet (rootful), since Podman's `--restart` flag alone doesn't survive a host reboot.

#### Still open

- **Weather** needs a weatherapi.com or openweathermap.org key. It only sends the location you ask about, never audio.
- **Face enrolment ("my name is …") fails.** The robot logs show `lost_enrollee` (he loses the face partway through) and once `SawWrongFace` (he matched an already-known face). That's a vision/enrolment problem on the robot, not wire-pod. Retry in good light, ~30–50 cm away, facing him and holding still. If it keeps saying you're someone else, an old enrolled face may need removing.
