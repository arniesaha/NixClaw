import Foundation
import SwiftUI

@MainActor
class GeminiSessionViewModel: ObservableObject {
  @Published var isGeminiActive: Bool = false
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var errorMessage: String?
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var isInBackground: Bool = false
  @Published var sessionDuration: TimeInterval = 0
  @Published var isAudioOnlyMode: Bool = false
  private let geminiService = GeminiLiveService()
  private let openClawBridge = OpenClawBridge()
  private var toolCallRouter: ToolCallRouter?
  private let audioManager = AudioManager()
  private var lastVideoFrameTime: Date = .distantPast
  private var lastVideoFrame: UIImage?  // Store for tool calls that need the current view

  /// Debug property to check if we have a video frame available
  var hasVideoFrame: Bool { lastVideoFrame != nil }
  private var stateObservation: Task<Void, Never>?
  private var sessionStartTime: Date?
  private var sessionTimer: Task<Void, Never>?
  private var shouldAutoReconnect = false
  private var reconnectAttempts = 0
  private let maxReconnectAttempts = 3

  var streamingMode: StreamingMode = .glasses
  var onPauseVideoCapture: (() -> Void)?
  var onResumeVideoCapture: (() -> Void)?

  init() {
    setupBackgroundObservers()
  }

  private func setupBackgroundObservers() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleEnterBackground),
      name: .appDidEnterBackground,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleEnterForeground),
      name: .appWillEnterForeground,
      object: nil
    )
  }

  @objc private func handleEnterBackground() {
    NSLog("[GeminiSession] Entering background mode - stopping video, keeping audio")
    isInBackground = true
    onPauseVideoCapture?()
  }

  @objc private func handleEnterForeground() {
    NSLog("[GeminiSession] Returning to foreground - resuming video")
    isInBackground = false
    if isGeminiActive {
      onResumeVideoCapture?()
    }
  }

  func startSession() async {
    guard !isGeminiActive else { return }

    guard GeminiConfig.isConfigured else {
      errorMessage = "Gemini API key not configured. Open Settings (gear icon) and enter your API key from https://aistudio.google.com/apikey"
      return
    }

    isGeminiActive = true

    // Wire audio callbacks
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self else { return }
      Task { @MainActor in
        // iPhone mode: mute mic while model speaks to prevent echo feedback
        // (loudspeaker + co-located mic overwhelms iOS echo cancellation)
        if self.streamingMode == .iPhone && self.geminiService.isModelSpeaking { return }
        self.geminiService.sendAudio(data: data)
      }
    }

    geminiService.onAudioReceived = { [weak self] data in
      self?.audioManager.playAudio(data: data)
    }

    geminiService.onInterrupted = { [weak self] in
      self?.audioManager.stopPlayback()
    }

    geminiService.onTurnComplete = { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        // Clear user transcript when AI finishes responding
        self.userTranscript = ""
      }
    }

    geminiService.onInputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.userTranscript += text
        self.aiTranscript = ""
      }
    }

    geminiService.onOutputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.aiTranscript += text
      }
    }

    // Handle unexpected disconnection with auto-reconnect
    geminiService.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        guard self.isGeminiActive else { return }

        let isServerTimeout = reason?.contains("Server closing") == true ||
                              reason?.contains("goAway") == true

        if isServerTimeout && self.shouldAutoReconnect && self.reconnectAttempts < self.maxReconnectAttempts {
          NSLog("[GeminiSession] Server timeout, attempting reconnect (\(self.reconnectAttempts + 1)/\(self.maxReconnectAttempts))")
          self.reconnectAttempts += 1
          self.connectionState = .connecting

          // Brief pause before reconnecting
          try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

          // Reconnect
          let success = await self.geminiService.connect()
          if success {
            NSLog("[GeminiSession] Reconnected successfully")
            self.reconnectAttempts = 0
            self.connectionState = .ready
          } else {
            self.stopSession()
            self.errorMessage = "Reconnection failed after server timeout"
          }
        } else {
          self.stopSession()
          if isServerTimeout {
            self.errorMessage = "Session ended (Gemini has a ~15 min limit). Tap to start a new session."
          } else {
            self.errorMessage = "Connection lost: \(reason ?? "Unknown error")"
          }
        }
      }
    }

    // New OpenClaw session per Gemini session (fresh context, no stale memory)
    openClawBridge.resetSession()

    // Wire tool call handling
    toolCallRouter = ToolCallRouter(bridge: openClawBridge)

    geminiService.onToolCall = { [weak self] toolCall in
      guard let self else { return }
      Task { @MainActor in
        for call in toolCall.functionCalls {
          // Pass the current video frame so tool calls can include images
          self.toolCallRouter?.handleToolCall(call, currentFrame: self.lastVideoFrame) { [weak self] response in
            self?.geminiService.sendToolResponse(response)
          }
        }
      }
    }

    geminiService.onToolCallCancellation = { [weak self] cancellation in
      guard let self else { return }
      Task { @MainActor in
        self.toolCallRouter?.cancelToolCalls(ids: cancellation.ids)
      }
    }

    // Observe service state and update Live Activity
    stateObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled else { break }
        self.connectionState = self.geminiService.connectionState
        self.isModelSpeaking = self.geminiService.isModelSpeaking
        self.toolCallStatus = self.openClawBridge.lastToolCallStatus

        // Update Live Activity
        GeminiLiveActivityManager.shared.updateActivity(
          isConnected: self.connectionState == .ready,
          isModelSpeaking: self.isModelSpeaking,
          duration: self.sessionDuration
        )
      }
    }

    // Setup audio
    // In audio-only mode, prefer Bluetooth (AirPods) if available for both input and output
    // This prevents audio from being routed to Ray-Ban glasses speaker
    do {
      let preferBluetooth = isAudioOnlyMode && audioManager.isBluetoothConnected
      try audioManager.setupAudioSession(
        useIPhoneMode: streamingMode == .iPhone,
        preferBluetooth: preferBluetooth
      )
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      isGeminiActive = false
      return
    }

    // Connect to Gemini and wait for setupComplete
    let setupOk = await geminiService.connect()

    if !setupOk {
      let msg: String
      if case .error(let err) = geminiService.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to Gemini"
      }
      errorMessage = msg
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }

    // Start mic capture
    do {
      try audioManager.startCapture()
    } catch {
      errorMessage = "Mic capture failed: \(error.localizedDescription)"
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }

    // Enable auto-reconnect and start session timer
    shouldAutoReconnect = true
    reconnectAttempts = 0
    sessionStartTime = Date()
    startSessionTimer()

    // Start Dynamic Island Live Activity
    GeminiLiveActivityManager.shared.startActivity()
  }

  private func startSessionTimer() {
    sessionTimer?.cancel()
    sessionTimer = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        guard !Task.isCancelled, let self, let start = self.sessionStartTime else { break }
        self.sessionDuration = Date().timeIntervalSince(start)
      }
    }
  }

  func stopSession() {
    shouldAutoReconnect = false
    sessionTimer?.cancel()
    sessionTimer = nil
    sessionStartTime = nil
    sessionDuration = 0
    toolCallRouter?.cancelAll()
    toolCallRouter = nil
    audioManager.stopCapture()
    geminiService.disconnect()
    stateObservation?.cancel()
    stateObservation = nil
    isGeminiActive = false
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle

    // End Dynamic Island Live Activity
    GeminiLiveActivityManager.shared.endActivity()
  }

  func sendVideoFrameIfThrottled(image: UIImage) {
    // ALWAYS store the latest frame for tool calls (even if we don't send it to Gemini)
    // This ensures lastVideoFrame is never nil when a tool call needs an image
    lastVideoFrame = image

    // Skip sending to Gemini in audio-only mode or when backgrounded
    guard !isAudioOnlyMode else { return }
    guard !isInBackground else { return }
    guard isGeminiActive, connectionState == .ready else { return }
    let now = Date()
    guard now.timeIntervalSince(lastVideoFrameTime) >= GeminiConfig.videoFrameInterval else { return }
    lastVideoFrameTime = now
    geminiService.sendVideoFrame(image: image)
  }

  /// Get the most recent video frame (for tool calls that need to include an image)
  func getLastVideoFrame() -> UIImage? {
    return lastVideoFrame
  }

  // MARK: - Audio Only Mode (Background-friendly, no video)

  /// Start an audio-only session for voice commands and tool calling.
  /// This mode works in background with Dynamic Island and doesn't require camera access.
  func startAudioOnlySession() async {
    guard !isGeminiActive else { return }

    guard GeminiConfig.isConfigured else {
      errorMessage = "Gemini API key not configured"
      return
    }

    isAudioOnlyMode = true
    streamingMode = .iPhone  // Use iPhone audio settings for best echo cancellation

    // Start the regular session - video frames will be skipped due to isAudioOnlyMode
    await startSession()

    if isGeminiActive {
      NSLog("[GeminiSession] Audio-only mode started (background-friendly)")
    }
  }

  func stopAudioOnlySession() {
    stopSession()
    isAudioOnlyMode = false
    NSLog("[GeminiSession] Audio-only mode stopped")
  }

}
