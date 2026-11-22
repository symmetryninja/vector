"""Test an LLM on wire-pod's real Vector prompt, before pointing wire-pod at it.

Usage: python3 llm/eval-wirepod-prompt.py [--runs N] NAME=ENDPOINT [NAME=ENDPOINT ...]
  e.g. small=http://127.0.0.1:8085/v1   (NAME is sent as the "model" field)

Streams each answer the way wire-pod does (temperature 1) and checks the {{command||param}}
syntax against wire-pod's command list. Emojis are reported but harmless: wire-pod strips them.

The prompt and command list are copied from wire-pod (chipper/pkg/wirepod/ttr/kgsim_cmds.go),
MIT licence, Copyright (c) 2022 Kerigan Creighton. Re-copy them if wire-pod changes its prompt.
"""
import json, re, sys, time, urllib.request

ANIMS = "happy, veryHappy, sad, verySad, angry, frustrated, dartingEyes, confused, thinking, celebrate, love"
CMDS = [
    ("playAnimationWI", "Plays an animation on the robot without interrupting speech. This should be used FAR more than the playAnimation command. This is great for storytelling and making any normal response animated. Don't put two of these right next to each other. Use this MANY times. The param choices are the only choices you have. You can't create any.", ANIMS),
    ("playAnimation", "Plays an animation on the robot. This will interrupt speech. Only use this if you are directed to play an animaion.", ANIMS),
    ("getImage", "Gets an image from the robot's camera and places it in the next message. If you want to do this, tell the user what you are about to do THEN use the command. This command should END a sentence. Your response will be stopped when this command is recognized. If a user says something like 'what do you see', you should assume that you need to take a new photo. Do NOT automatically assume that you are analyzing a previous photo.", "front, lookingUp"),
    ("newVoiceRequest", "Starts a new voice command from the robot. Use this if you want more input from the user after your response/if you want to carry out a conversation. Below this, there should be a NOTE telling you whether you are in conversation mode or not. If you are, DONT BE AFRAID TO USE THIS COMMAND! This goes at the end of your response, if you use it.", "now"),
]
VALID = {c: {p.strip() for p in ps.split(",")} for c, _, ps in CMDS}

prompt = "You are a helpful, animated robot called Vector. Keep the response concise yet informative."
prompt += "\n\nKeep in mind, user input comes from speech-to-text software, so respond accordingly. No special characters, especially these: & ^ * # @ - . No lists. No formatting."
prompt += "\n\nYou are running ON an Anki Vector robot. You have a set of commands. If you include an emoji, I will make you start over. If you want to use a command but it doesn't exist or your desired parameter isn't in the list, avoid using the command. The format is {{command||parameter}}. You can embed these in sentences. Example: \"User: How are you feeling? | Response: \"{{playAnimationWI||sad}} I'm feeling sad...\". Square brackets ([]) are not valid.\n\nUse the playAnimation or playAnimationWI commands if you want to express emotion! You are very animated and good at following instructions. Animation takes precendence over words. You are to include many animations in your response.\n\nHere is every valid command:"
for c, d, p in CMDS:
    prompt += f"\n\nCommand Name: {c}\nDescription: {d}\nParameter choices: {p}"
prompt += "\n\nNOTE: You are in 'conversation' mode. If you ask the user a question near the end of your response, you MUST use newVoiceRequest. If you decide you want to end the conversation, you should not use it."

QUESTIONS = [
    "what is the tallest mountain in australia",
    "how are you feeling today",
    "tell me a short story about a spider robot",
    "what do you see",
    "why is the sky blue",
    "i had a really bad day at work",
    "what's seven times eight",
    "do you want to play a game",
    "who are you",
    "explain how a transistor works in one sentence",
]
EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿]")


def ask(url, model, q):
    body = json.dumps({"model": model, "messages": [{"role": "system", "content": prompt}, {"role": "user", "content": q}],
                       "max_tokens": 2048, "temperature": 1, "top_p": 1, "stream": True}).encode()
    req = urllib.request.Request(url + "/chat/completions", body, {"Content-Type": "application/json"})
    t0 = time.time(); first = None; out = []
    with urllib.request.urlopen(req, timeout=120) as r:
        for line in r:
            line = line.decode().strip()
            if not line.startswith("data:") or line.endswith("[DONE]"):
                continue
            delta = json.loads(line[5:])["choices"][0]["delta"].get("content") or ""
            if delta and first is None:
                first = time.time() - t0
            out.append(delta)
    return "".join(out), first or 0, time.time() - t0


def check(text):
    problems = []
    for cmd, param in re.findall(r"\{\{([^}|]*)\|\|([^}]*)\}\}", text):
        if cmd.strip() not in VALID or param.strip() not in VALID[cmd.strip()]:
            problems.append(f"bad {{{{{cmd}||{param}}}}}")
    stripped = re.sub(r"\{\{[^}]*\}\}", "", text)
    if "{" in stripped or "}" in stripped or "[" in stripped:
        problems.append("stray brackets")
    if EMOJI.search(text):
        problems.append("emoji")
    if re.search(r"^\s*([-*]|\d+\.)\s", stripped, re.M) or "**" in stripped or "#" in stripped:
        problems.append("formatting")
    if "<think>" in text:
        problems.append("thinking")
    return problems, len(re.findall(r"\{\{", text))


args = sys.argv[1:]
runs = 1
if args[:1] == ["--runs"]:
    runs, args = int(args[1]), args[2:]
if not args:
    sys.exit(__doc__)

for arg in args * runs:
    name, url = arg.split("=", 1)
    ttfts, totals, bad, anims = [], [], 0, 0
    print(f"\n######## {name}")
    for q in QUESTIONS:
        text, ttft, total = ask(url, name, q)
        problems, n = check(text)
        ttfts.append(ttft); totals.append(total); anims += n; bad += bool(problems)
        print(f"\n> {q}   [first token {ttft:.2f}s, done {total:.2f}s, {n} cmds{', PROBLEMS: ' + ', '.join(problems) if problems else ''}]")
        print("  " + text.strip().replace("\n", " ")[:600])
    print(f"\n== {name}: median first token {sorted(ttfts)[5]:.2f}s, median total {sorted(totals)[5]:.2f}s, "
          f"answers with problems {bad}/10, commands used {anims}")
