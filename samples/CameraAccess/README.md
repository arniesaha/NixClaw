# VisionClaw

A real-time AI assistant for Meta Ray-Ban smart glasses. See what you see, hear what you say, and take actions on your behalf -- all through voice.

Built on [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios) + [Gemini Live API](https://ai.google.dev/gemini-api/docs/live) + [OpenClaw](https://github.com/nichochar/openclaw) (optional).

## What It Does

Put on your glasses, tap the AI button, and talk:

- **"What am I looking at?"** -- Gemini sees through your glasses camera and describes the scene
- **"Add milk to my shopping list"** -- delegates to OpenClaw, which adds it via your connected apps
- **"Send a message to John saying I'll be late"** -- routes through OpenClaw to WhatsApp/Telegram/iMessage
- **"Search for the best coffee shops nearby"** -- web search via OpenClaw, results spoken back

The glasses camera streams at ~1fps to Gemini for visual context, while audio flows bidirectionally in real-time.

## How It Works

```
Meta Ray-Ban Glasses (or iPhone camera)
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
- **Gemini Live** -- real-time voice + vision AI over WebSocket (native audio, not STT-first)
- **OpenClaw** (optional) -- local gateway that gives Gemini access to 56+ tools and all your connected apps
- **iPhone mode** -- test the full pipeline using your iPhone camera instead of glasses

## Quick Start

### 1. Clone and open

```bash
git clone https://github.com/sseanliu/VisionClaw.git
cd VisionClaw/samples/CameraAccess
open CameraAccess.xcodeproj
```

### 2. Add your Gemini API key

Get a free API key at [Google AI Studio](https://aistudio.google.com/apikey).

Open `CameraAccess/Gemini/GeminiConfig.swift` and replace the placeholder:

```swift
static let apiKey = "YOUR_GEMINI_API_KEY"  // <-- paste your key here
```

### 3. Build and run

Select your iPhone as the target device and hit Run (Cmd+R).

### 4. Try it out

**Without glasses (iPhone mode):**
1. Tap **"Start on iPhone"** -- uses your iPhone's back camera
2. Tap the **AI button** to start a Gemini Live session
3. Talk to the AI -- it can see through your iPhone camera

**With Meta Ray-Ban glasses:**
1. Pair your glasses via the Meta AI app (enable Developer Mode)
2. Tap **"Start Streaming"** in the app
3. Tap the **AI button** for voice + vision conversation

## Setup: OpenClaw (Optional)

OpenClaw gives Gemini the ability to take real-world actions: send messages, search the web, manage lists, control smart home devices, and more. Without it, Gemini is voice + vision only.

### 1. Install and configure OpenClaw

Follow the [OpenClaw setup guide](https://github.com/nichochar/openclaw). Make sure the gateway is enabled:

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
- `bind: "lan"` -- exposes the gateway on your local network so your iPhone can reach it
- `chatCompletions.enabled: true` -- enables the `/v1/chat/completions` endpoint (off by default)
- `auth.token` -- the token your iOS app will use to authenticate

### 2. Configure the iOS app

In `GeminiConfig.swift`, update the OpenClaw settings:

```swift
static let openClawHost = "http://Your-Mac.local"           // your Mac's Bonjour hostname
static let openClawPort = 18789
static let openClawGatewayToken = "your-gateway-token-here"  // must match gateway.auth.token
```

To find your Mac's Bonjour hostname: **System Settings > General > Sharing** -- it's shown at the top (e.g., `Johns-MacBook-Pro.local`).

### 3. Start the gateway

```bash
openclaw gateway restart
```

Verify it's running:

```bash
curl http://localhost:18789/health
```

Now when you talk to the AI, it can execute tasks through OpenClaw.

## Architecture

### Key Files

| File | Purpose |
|------|---------|
| `Gemini/GeminiConfig.swift` | API keys, model config, system prompt |
| `Gemini/GeminiLiveService.swift` | WebSocket client for Gemini Live API |
| `Gemini/AudioManager.swift` | Mic capture (PCM 16kHz) + audio playback (PCM 24kHz) |
| `Gemini/GeminiSessionViewModel.swift` | Session lifecycle, tool call wiring, transcript state |
| `OpenClaw/ToolCallModels.swift` | Tool declarations, data types |
| `OpenClaw/OpenClawBridge.swift` | HTTP client for OpenClaw gateway |
| `OpenClaw/ToolCallRouter.swift` | Routes Gemini tool calls to OpenClaw |
| `iPhone/IPhoneCameraManager.swift` | AVCaptureSession wrapper for iPhone camera mode |

### Audio Pipeline

- **Input**: iPhone mic -> AudioManager (PCM Int16, 16kHz mono, 100ms chunks) -> Gemini WebSocket
- **Output**: Gemini WebSocket -> AudioManager playback queue -> iPhone speaker
- **iPhone mode**: Uses `.voiceChat` audio session for echo cancellation + mic gating during AI speech
- **Glasses mode**: Uses `.videoChat` audio session (mic is on glasses, speaker is on phone -- no echo)

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
- Meta Ray-Ban glasses (optional -- use iPhone mode for testing)
- OpenClaw on your Mac (optional -- for agentic actions)

## Troubleshooting

**"Gemini API key not configured"** -- Open `GeminiConfig.swift` and add your API key.

**OpenClaw connection timeout** -- Make sure your iPhone and Mac are on the same Wi-Fi network, the gateway is running (`openclaw gateway restart`), and the hostname in `GeminiConfig.swift` matches your Mac's Bonjour name.

**Echo/feedback in iPhone mode** -- The app mutes the mic while the AI is speaking. If you still hear echo, try turning down the volume.

**Gemini doesn't hear me** -- Check that microphone permission is granted. The app uses aggressive voice activity detection -- speak clearly and at normal volume.

For DAT SDK issues, see the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or the [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

## License

This source code is licensed under the license found in the [LICENSE](../../LICENSE) file in the root directory of this source tree.
