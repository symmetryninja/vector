# 07: MCP tools for Vector's voice assistant

Status: backlog (approach chosen 2026-11-24, not started)

## Goal

Let the model behind "Hey Vector" use MCP tools, starting with Home Assistant, so a question like "are the workshop lights turned off?" gets a real answer.

## Chosen approach: an MCP proxy between wire-pod and llama.cpp

```
wire-pod  →  proxy (OpenAI-compatible, MCP client)  →  llama.cpp (Qwen3-4B)
                         ↕
               MCP servers (Home Assistant first)
```

- wire-pod is unchanged: only its `custom` endpoint moves to the proxy (`just wirepod-ai`).
- The proxy adds the MCP tools to each request, runs the tool calls itself, and returns plain text with wire-pod's usual `{{command||param}}` tags.
- It must **stream** the final answer (wire-pod speaks sentence by sentence; see docs/03). While a tool runs, it can stream a short "Let me check…" first so Vector isn't silent.
- Tailnet/localhost only, like everything else here: the proxy has no auth.

Alternatives considered and set aside:

- **Hand non-command speech to Home Assistant's Assist**: fast and reliable for home questions, but Vector loses his personality and animations, it's tied to Home Assistant only, and it isn't MCP.
- **wire-pod custom intents** (fixed phrase → script → HA REST API): instant and deterministic, but needs a rule per question.

## Findings

- 2026-11-24: wire-pod sends a streamed `ChatCompletionRequest` with no `tools` field (`chipper/pkg/wirepod/ttr/kgsim.go`, `CreateAIReq`). Its only "tools" are text tags the model writes, which wire-pod acts out. So tool use has to happen outside wire-pod, hence the proxy.
- Home Assistant has an official MCP Server integration that exposes the Assist tools (state, on/off and so on) for entities exposed to Assist. Whether it's enabled on our HA VM: to confirm.
- Qwen3-4B-Instruct-2507 supports tool calls (docs/03). How reliably it picks the right tool with wire-pod's long prompt is to confirm: add tool cases to `just llm-eval` first.

## Open questions and risks

- **Read-only first?** HA's MCP tools can switch things as well as read them, and anyone in the room can talk to Vector. Use HA's expose list, and possibly a proxy-side allowlist that blocks switching tools at first.
- **Latency:** each tool round adds a model pass (~1–2 s on the 4B model) plus the tool's own time.
- **Privacy:** audio stays local, but any MCP server backed by an outside service receives the transcript. HA is local, so it's fine.
- **Who's asking:** see "Speaker and face identity" below.

## Later: speaker and face identity

To confirm before relying on any of it. Notes from 2026-11-24:

- **Faces:** Vector's own face enrolment ("my name is …") runs on the robot and the SDK reports recognised faces, so the proxy could ask "who is he looking at right now?" when a request arrives. It's a convenience feature for his personality, not a security one, and enrolment is currently failing (docs/03). Better accuracy: pull camera frames to the server and run an open face-embedding model there. The robot's low camera angle and lighting still limit it.
- **Voice:** wire-pod receives the audio for speech-to-text (Vosk), but the proxy only sees text, so voice ID needs a wire-pod change. Vosk has a speaker-embedding model, and SpeechBrain's ECAPA models are Apache-2.0. Short far-field commands in a noisy workshop make it unreliable as proof of who's speaking.
- Either way, treat identity as a hint for personalisation, not authorisation. Anything risky needs a confirmation that can't be faked by a recording or a photo.
