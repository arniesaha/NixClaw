# NixClaw

> Forked from [VisionClaw](https://github.com/sseanliu/VisionClaw)

![NixClaw](assets/teaserimage.png)

A multi-mode AI assistant — through Meta Ray-Ban smart glasses, iPhone camera, or just voice. See what you see, hear what you say, and take actions on your behalf.

![Cover](assets/cover.png)

Built on [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios) + [Gemini Live API](https://ai.google.dev/gemini-api/docs/live) + [OpenClaw](https://github.com/nichochar/openclaw).

## Backstory

NixClaw started from a conversation with **Nix**, my personal [OpenClaw](https://github.com/nichochar/openclaw) agent. I was using VisionClaw to stream video from Meta Ray-Ban glasses to Gemini, but it was limited to voice + vision — it couldn't actually *do* anything. Meanwhile, Nix could send messages, search the web, manage my lists, control smart home devices, and more — but had no eyes or ears.

NixClaw bridges the two: Gemini handles the real-time voice and vision conversation, and when you ask it to take an action, it delegates to your OpenClaw agent. The name is literally **Nix** + Open**Claw** — the AI assistant that can see, hear, *and* act.

The audio-only and background modes exist specifically for this: you can have a hands-free conversation with your agent while walking around, and it keeps running when you lock your phone.

## What It Does

Choose your mode and talk:

- **Smart Glasses** — Gemini sees through your Meta Ray-Ban camera and responds in real-time
- **Audio Only** — Voice conversations with AI using any audio device (AirPods, speakers, built-in mic), continues in background
- **iPhone Camera** — Use your iPhone camera for visual AI without glasses

Example commands:
- **"What am I looking at?"** — Gemini sees through your camera and describes the scene
- **"Add milk to my shopping list"** — delegates to OpenClaw, which adds it via your connected apps
- **"Send a message to John saying I'll be late"** — routes through OpenClaw to WhatsApp/Telegram/iMessage
- **"Search for the best coffee shops nearby"** — web search via OpenClaw, results spoken back

## How It Works

![How It Works](assets/how.png)

```
Meta Ray-Ban Glasses / iPhone Camera / Audio Only
       |
       | video frames + mic audio
       v
iOS App (this project)
       |
       | JPEG frames (~1fps) + PCM audio (16kHz)
       v
Gemini Live API (WebSocket)
       |
       |-- Audio response (PCM 24kHz) --> iOS App --> Speaker
       |-- Tool calls (execute) -------> iOS App --> OpenClaw Gateway
       |                                                  |
       |                                                  v
       |                                          56+ skills: web search,
       |                                          messaging, smart home,
       |                                          notes, reminders, etc.
       |                                                  |
       |<---- Tool response (text) <----- iOS App <-------+
       |
       v
  Gemini speaks the result
```

**Key pieces:**
- **Gemini Live** — real-time voice + vision AI over WebSocket (native audio, not STT-first)
- **OpenClaw** — local gateway that gives Gemini access to 56+ tools and all your connected apps
- **Three modes** — glasses (video + audio), iPhone camera (video + audio), audio-only (any device, runs in background)

## Quick Start

### 1. Set up OpenClaw

NixClaw is designed to work with an [OpenClaw](https://github.com/nichochar/openclaw) agent. Without it, you get voice + vision but no ability to take actions — which is the whole point.

Follow the [OpenClaw setup guide](https://github.com/nichochar/openclaw) to install and configure your agent. Make sure the gateway is enabled:

In `~/.openclaw/openclaw.json`:

```json
{
  "gateway": {
    "port": 18789,
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "your-gateway-token-here"
    },
    "http": {
      "endpoints": {
        "chatCompletions": { "enabled": true }
      }
    }
  }
}
```

Key settings:
- `bind: "lan"` — exposes the gateway on your local network so your iPhone can reach it
- `chatCompletions.enabled: true` — enables the `/v1/chat/completions` endpoint (off by default)
- `auth.token` — the token your iOS app will use to authenticate

Start the gateway:

```bash
openclaw gateway restart
```

Verify it's running:

```bash
curl http://localhost:18789/health
```

### 2. Clone and open

```bash
git clone https://github.com/arniesaha/NixClaw.git
cd NixClaw
open NixClaw.xcodeproj
```

### 3. Configure

Copy the template config:

```bash
cp Config/NixClaw.xcconfig Config/Nix.xcconfig
```

Edit `Config/Nix.xcconfig` and fill in your values:

```
GEMINI_API_KEY = your-gemini-api-key
DEFAULT_OPENCLAW_SCHEME = http
DEFAULT_OPENCLAW_HOSTNAME = Your-Mac.local
DEFAULT_OPENCLAW_PORT = 18789
DEFAULT_OPENCLAW_TOKEN = your-gateway-token-here
```

Get a free Gemini API key at [Google AI Studio](https://aistudio.google.com/apikey).

To find your Mac's hostname: **System Settings > General > Sharing** — it's shown at the top (e.g., `Johns-MacBook-Pro.local`).

> **Note:** The scheme and hostname are separate because `//` in URLs is interpreted as a comment by the xcconfig parser.

Then in Xcode, set the configuration file: **Project > Info > Configurations > set all to `Nix.xcconfig`**.

Alternatively, skip the xcconfig step — the app will show a setup wizard on first launch where you can enter everything.

### 4. Build and run

Select your iPhone as the target device and hit Run (Cmd+R).

### 5. Try it out

From the home screen, choose your mode:

**Audio Only:**
1. Tap **"Audio Only"** — starts a voice conversation using your current audio device
2. Talk to the AI — no camera needed, keeps running in background

**iPhone Camera:**
1. Tap **"iPhone Camera"** — uses your iPhone's back camera
2. Talk to the AI — it can see through your iPhone camera

**With Meta Ray-Ban glasses:**

First, enable Developer Mode in the Meta AI app:

1. Open the **Meta AI** app on your iPhone
2. Go to **Settings** (gear icon, bottom left)
3. Tap **App Info**
4. Tap the **App version** number **5 times** — this unlocks Developer Mode
5. Go back to Settings — you'll now see a **Developer Mode** toggle. Turn it on.

![How to enable Developer Mode](assets/dev_mode.png)

Then in NixClaw:
1. Tap **"Connect Glasses"** in the app
2. Tap the **AI button** for voice + vision conversation

## Architecture

### Key Files

All source code is in `NixClaw/`:

| File | Purpose |
|------|---------|
| `Config/AppConfig.swift` | Centralized runtime config (UserDefaults > Info.plist > fallback) |
| `Config/SetupWizardView.swift` | First-launch setup wizard |
| `Config/SettingsView.swift` | Runtime settings UI |
| `Gemini/GeminiConfig.swift` | Model config, system prompt (reads from AppConfig) |
| `Gemini/GeminiLiveService.swift` | WebSocket client for Gemini Live API |
| `Gemini/AudioManager.swift` | Mic capture (PCM 16kHz) + audio playback (PCM 24kHz) |
| `Gemini/GeminiSessionViewModel.swift` | Session lifecycle, tool call wiring, transcript state |
| `OpenClaw/ToolCallModels.swift` | Tool declarations, data types |
| `OpenClaw/OpenClawBridge.swift` | HTTP client for OpenClaw gateway |
| `OpenClaw/ToolCallRouter.swift` | Routes Gemini tool calls to OpenClaw |
| `iPhone/IPhoneCameraManager.swift` | AVCaptureSession wrapper for iPhone camera mode |
| `Background/BackgroundModeManager.swift` | App lifecycle and background mode transitions |

### Audio Pipeline

- **Input**: iPhone mic -> AudioManager (PCM Int16, 16kHz mono, 100ms chunks) -> Gemini WebSocket
- **Output**: Gemini WebSocket -> AudioManager playback queue -> iPhone speaker
- **iPhone mode**: Uses `.voiceChat` audio session for echo cancellation + mic gating during AI speech
- **Glasses mode**: Uses `.videoChat` audio session (mic is on glasses, speaker is on phone — no echo)

### Video Pipeline

- **Glasses**: DAT SDK `videoFramePublisher` (24fps) -> throttle to ~1fps -> JPEG (50% quality) -> Gemini
- **iPhone**: `AVCaptureSession` back camera (30fps) -> throttle to ~1fps -> JPEG -> Gemini

### Tool Calling

Gemini Live supports function calling. This app declares a single `execute` tool that routes everything through OpenClaw:

1. User says "Add eggs to my shopping list"
2. Gemini speaks "Sure, adding that now" (verbal acknowledgment before tool call)
3. Gemini sends `toolCall` with `execute(task: "Add eggs to the shopping list")`
4. `ToolCallRouter` sends HTTP POST to OpenClaw gateway
5. OpenClaw executes the task using its 56+ connected skills
6. Result returns to Gemini via `toolResponse`
7. Gemini speaks the confirmation

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Gemini API key ([get one free](https://aistudio.google.com/apikey))
- [OpenClaw](https://github.com/nichochar/openclaw) running on your Mac
- Meta Ray-Ban glasses (optional — use iPhone camera or audio-only mode)

## Troubleshooting

**"Gemini API key not configured"** — Enter your API key in the setup wizard or in Settings.

**OpenClaw connection timeout** — Make sure your iPhone and Mac are on the same Wi-Fi network, the gateway is running (`openclaw gateway restart`), and the hostname in your config matches your Mac's Bonjour name.

**Echo/feedback in iPhone mode** — The app mutes the mic while the AI is speaking. If you still hear echo, try turning down the volume.

**Gemini doesn't hear me** — Check that microphone permission is granted. The app uses aggressive voice activity detection — speak clearly and at normal volume.

For DAT SDK issues, see the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or the [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

## License

This source code is licensed under the license found in the [LICENSE](LICENSE) file in the root directory of this source tree.
