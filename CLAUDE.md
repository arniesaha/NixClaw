# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NixClaw is a multi-mode AI assistant iOS app (forked from VisionClaw) that enables real-time voice and vision conversations via Google's Gemini Live API. Three modes: Smart Glasses (Meta Ray-Ban), iPhone Camera, and Audio-Only. Optional OpenClaw integration for tool calling (web search, messaging, smart home, etc.).

## Build & Run

- **Xcode project:** `open NixClaw.xcodeproj`
- **Build:** Cmd+R targeting an iPhone (iOS 17.0+, Xcode 15.0+, Swift 5.9+)
- **Run tests:** `xcodebuild test -project NixClaw.xcodeproj -scheme NixClaw`

## Configuration System

Two-tier xcconfig setup in `Config/`:
- `NixClaw.xcconfig`: template for open source (no secrets)
- `Nix.xcconfig`: personal build with credentials (gitignored)

**Config flow:** xcconfig → Info.plist (build-time) → `AppConfig.swift` reads at runtime with priority: UserDefaults > Info.plist > hardcoded defaults. `@Published` properties auto-persist to UserDefaults via `didSet`.

**xcconfig gotcha:** `//` in URLs is treated as a comment by the xcconfig parser. OpenClaw host is split into `DEFAULT_OPENCLAW_SCHEME` and `DEFAULT_OPENCLAW_HOSTNAME` to avoid this. The URL is reconstructed at runtime in `AppConfig.openClawBaseURL`.

If `AppConfig.needsSetup` is true (no Gemini API key), the app shows `SetupWizardView` on first launch.

## Architecture

### Core Data Flow
```
Camera/Mic → iOS App → Gemini Live API (WebSocket)
                ↕                    ↕
           OpenClaw Gateway    Audio/Tool responses
```

### Key Layers

**Gemini/**: AI conversation engine
- `GeminiLiveService.swift`: WebSocket client (`wss://generativelanguage.googleapis.com/ws/...`), manages connection state enum, sends/receives audio+video
- `AudioManager.swift`: AVAudioEngine-based mic capture (16kHz PCM Int16, ~100ms chunks) + playback (24kHz PCM). Uses `.voiceChat` session for iPhone mode (echo cancellation), `.videoChat` for glasses mode
- `GeminiSessionViewModel.swift`: Orchestrates session lifecycle: connect → setup audio/video → wire callbacks → handle tool calls → cleanup
- `GeminiConfig.swift`: Model selection, API key, system prompt (reads from AppConfig)

**OpenClaw/**: Optional tool calling
- `OpenClawBridge.swift`: HTTP POST to `{host}:{port}/v1/chat/completions` with bearer token auth
- `ToolCallRouter.swift`: Routes Gemini function calls to OpenClaw, tracks in-flight tasks by ID, supports cancellation
- `ToolCallModels.swift`: Tool definitions and data types

**Background/**: Lifecycle management
- `BackgroundModeManager.swift`: Posts notifications for background/foreground transitions. Video pauses in background, audio continues.
- `GeminiLiveActivity.swift`: Dynamic Island / Live Activity support

**iPhone/**: Camera capture
- `IPhoneCameraManager.swift`: AVCaptureSession wrapper, back camera at 30fps throttled to ~1fps JPEG

### Video Pipeline
Both glasses (DAT SDK, 24fps) and iPhone camera (30fps) throttle to ~1fps, encode as JPEG at 50% quality, and send to Gemini via WebSocket.

## Key Patterns

- **@MainActor** on all ObservableObject classes for thread safety
- **async/await** throughout for concurrency
- **@EnvironmentObject** for dependency injection (`AppConfig`, `BackgroundModeManager`)
- **Combine** for lifecycle event observation via NotificationCenter publishers
- **#if DEBUG** gates Mock Device Kit for glasses simulation without hardware

## External Dependencies

- **Meta Wearables DAT SDK** (`MWDATCore`, `MWDATMockDevice`): Ray-Ban glasses integration, initialized via `Wearables.configure()` in `NixClawApp.swift`
- **Google Gemini Live API**: real-time voice/vision AI over WebSocket

## Logging

Uses `NSLog` with bracketed tags: `[NixClaw]`, `[GeminiSession]`, `[AudioManager]`, `[Gemini]`, `[OpenClaw]`, `[BackgroundMode]`.
