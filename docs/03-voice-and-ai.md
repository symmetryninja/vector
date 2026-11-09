# 3. Voice and AI conversation

Goal: talk to Vector properly. He should answer questions and hold a conversation using an AI service we choose, with our own API key.

Status: **not started**

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
