import AVFoundation
import Foundation

class AudioManager {
  var onAudioCaptured: ((Data) -> Void)?
  var onAudioRouteChanged: ((String) -> Void)?

  private let audioEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var isCapturing = false
  private var isPaused = false

  private let outputFormat: AVAudioFormat

  // Accumulate resampled PCM into ~100ms chunks before sending
  private let sendQueue = DispatchQueue(label: "audio.accumulator")
  private var accumulatedData = Data()
  private let minSendBytes = 3200  // 100ms at 16kHz mono Int16 = 1600 frames * 2 bytes

  /// Current audio input device name (e.g., "AirPods Pro", "iPhone Microphone")
  var currentInputDevice: String {
    let session = AVAudioSession.sharedInstance()
    if let input = session.currentRoute.inputs.first {
      return input.portName
    }
    return "Unknown"
  }

  /// Current audio output device name
  var currentOutputDevice: String {
    let session = AVAudioSession.sharedInstance()
    if let output = session.currentRoute.outputs.first {
      return output.portName
    }
    return "Unknown"
  }

  /// Check if Bluetooth audio (AirPods, etc.) is connected
  var isBluetoothConnected: Bool {
    let session = AVAudioSession.sharedInstance()
    let inputs = session.currentRoute.inputs
    let outputs = session.currentRoute.outputs

    let bluetoothTypes: [AVAudioSession.Port] = [
      .bluetoothA2DP, .bluetoothLE, .bluetoothHFP
    ]

    let hasBluetoothInput = inputs.contains { bluetoothTypes.contains($0.portType) }
    let hasBluetoothOutput = outputs.contains { bluetoothTypes.contains($0.portType) }

    return hasBluetoothInput || hasBluetoothOutput
  }

  init() {
    self.outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: true
    )!
    setupNotificationHandling()
  }

  private func setupNotificationHandling() {
    let session = AVAudioSession.sharedInstance()

    // Audio interruption handling (phone calls, Siri, etc.)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: session
    )

    // Audio route change handling (AirPods connect/disconnect, etc.)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: session
    )
  }

  @objc private func handleRouteChange(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
      return
    }

    let session = AVAudioSession.sharedInstance()
    let currentInput = session.currentRoute.inputs.first?.portName ?? "None"
    let currentOutput = session.currentRoute.outputs.first?.portName ?? "None"

    switch reason {
    case .newDeviceAvailable:
      NSLog("[AudioManager] New audio device available - Input: %@, Output: %@", currentInput, currentOutput)
      onAudioRouteChanged?(currentOutput)

      // If Bluetooth device connected and we're capturing, switch to it
      // Check availableInputs (not currentRoute) since the route hasn't switched yet
      if isCapturing {
        let hasBluetoothAvailable = session.availableInputs?.contains { input in
          let bluetoothTypes: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothLE, .bluetoothA2DP]
          return bluetoothTypes.contains(input.portType)
        } ?? false

        if hasBluetoothAvailable {
          NSLog("[AudioManager] Bluetooth connected mid-session, switching audio route")
          switchToBluetoothIfAvailable()
        }
      }

    case .oldDeviceUnavailable:
      NSLog("[AudioManager] Audio device disconnected - Input: %@, Output: %@", currentInput, currentOutput)
      onAudioRouteChanged?(currentOutput)
      // Reconfigure audio session when Bluetooth disconnects
      if isCapturing {
        reconfigureAudioEngine()
      }

    case .categoryChange:
      NSLog("[AudioManager] Audio category changed")

    case .override:
      NSLog("[AudioManager] Audio route override")

    default:
      NSLog("[AudioManager] Audio route changed (reason: %d) - Input: %@, Output: %@",
            reason.rawValue, currentInput, currentOutput)
    }
  }

  /// Switch audio input/output to Bluetooth device if available
  private func switchToBluetoothIfAvailable() {
    let session = AVAudioSession.sharedInstance()

    // Find Bluetooth input
    guard let bluetoothInput = session.availableInputs?.first(where: { input in
      let bluetoothTypes: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothLE, .bluetoothA2DP]
      return bluetoothTypes.contains(input.portType)
    }) else {
      NSLog("[AudioManager] No Bluetooth input available")
      return
    }

    do {
      // First, reconfigure session WITHOUT .defaultToSpeaker to allow Bluetooth output
      // .defaultToSpeaker forces output to speaker even when Bluetooth is connected
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [
          .allowBluetoothHFP,
          .allowBluetoothA2DP,
          .mixWithOthers
          // Note: NO .defaultToSpeaker - this allows Bluetooth to take over output
        ]
      )

      // Set Bluetooth as preferred input - this also routes output to Bluetooth for HFP
      try session.setPreferredInput(bluetoothInput)
      NSLog("[AudioManager] Switched to Bluetooth: %@", bluetoothInput.portName)

      // Log new route after a brief delay for route to settle
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        let newInput = session.currentRoute.inputs.first?.portName ?? "None"
        let newOutput = session.currentRoute.outputs.first?.portName ?? "None"
        NSLog("[AudioManager] New route - Input: %@, Output: %@", newInput, newOutput)
      }
    } catch {
      NSLog("[AudioManager] Failed to switch to Bluetooth: %@", error.localizedDescription)
    }
  }

  /// Reconfigure audio engine after route change (e.g., AirPods disconnected)
  /// Note: For major format changes (like Bluetooth HFP), it's safer to stop and restart
  /// the entire capture session rather than trying to reconfigure mid-stream
  private func reconfigureAudioEngine() {
    NSLog("[AudioManager] Reconfiguring audio engine after route change")

    // For now, just try to keep the engine running
    // Major format changes (like switching to/from Bluetooth HFP) may require
    // a full session restart from the caller
    do {
      if !audioEngine.isRunning {
        try AVAudioSession.sharedInstance().setActive(true)
        try audioEngine.start()
        playerNode.play()
        NSLog("[AudioManager] Audio engine restarted successfully")
      } else {
        NSLog("[AudioManager] Audio engine still running, no reconfiguration needed")
      }
    } catch {
      NSLog("[AudioManager] Failed to reconfigure audio engine: %@", error.localizedDescription)
      // The engine may be in a bad state - caller should restart the session
    }
  }

  @objc private func handleInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .began:
      NSLog("[AudioManager] Interruption began (phone call, Siri, etc.)")
      pauseAudio()

    case .ended:
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
          NSLog("[AudioManager] Interruption ended, resuming audio")
          resumeAudio()
        }
      }

    @unknown default:
      break
    }
  }

  func pauseAudio() {
    guard isCapturing, !isPaused else { return }
    isPaused = true
    audioEngine.pause()
    NSLog("[AudioManager] Audio paused")
  }

  func resumeAudio() {
    guard isCapturing, isPaused else { return }
    isPaused = false
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      try audioEngine.start()
      playerNode.play()
      NSLog("[AudioManager] Audio resumed")
    } catch {
      NSLog("[AudioManager] Failed to resume audio: %@", error.localizedDescription)
    }
  }

  func setupAudioSession(useIPhoneMode: Bool = false, preferBluetooth: Bool = false) throws {
    let session = AVAudioSession.sharedInstance()
    // iPhone mode: voiceChat for aggressive echo cancellation (mic + speaker co-located)
    // Glasses mode: videoChat for mild AEC (mic is on glasses, speaker is on phone)
    let mode: AVAudioSession.Mode = useIPhoneMode ? .voiceChat : .videoChat

    // Build options based on requirements
    var options: AVAudioSession.CategoryOptions = [
      .allowBluetoothHFP,    // HFP for calls/voice (AirPods mic + speaker)
      .allowBluetoothA2DP,   // High-quality audio output
      .mixWithOthers         // Required for background audio
    ]

    // Only add .defaultToSpeaker if NOT preferring Bluetooth
    // .defaultToSpeaker routes to speaker even when Bluetooth is available
    if !preferBluetooth {
      options.insert(.defaultToSpeaker)
    }

    try session.setCategory(
      .playAndRecord,
      mode: mode,
      options: options
    )
    try session.setPreferredSampleRate(GeminiConfig.inputAudioSampleRate)
    try session.setPreferredIOBufferDuration(0.064)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    // If preferring Bluetooth and it's available, set the preferred input explicitly
    if preferBluetooth {
      if let bluetoothInput = session.availableInputs?.first(where: { input in
        let bluetoothTypes: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothLE, .bluetoothA2DP]
        return bluetoothTypes.contains(input.portType)
      }) {
        try session.setPreferredInput(bluetoothInput)
        NSLog("[Audio] Set preferred input to Bluetooth: %@", bluetoothInput.portName)
      }
    }

    // Log current audio route
    let inputDevice = session.currentRoute.inputs.first?.portName ?? "None"
    let outputDevice = session.currentRoute.outputs.first?.portName ?? "None"
    let inputType = session.currentRoute.inputs.first?.portType.rawValue ?? "unknown"
    let outputType = session.currentRoute.outputs.first?.portType.rawValue ?? "unknown"

    NSLog("[Audio] Session configured - Mode: %@, PreferBluetooth: %@",
          useIPhoneMode ? "voiceChat" : "videoChat",
          preferBluetooth ? "YES" : "NO")
    NSLog("[Audio] Input: %@ (%@)", inputDevice, inputType)
    NSLog("[Audio] Output: %@ (%@)", outputDevice, outputType)
    NSLog("[Audio] Bluetooth connected: %@", isBluetoothConnected ? "YES" : "NO")
  }

  func startCapture() throws {
    guard !isCapturing else { return }

    // Reset audio engine to clean state before starting
    // This ensures we don't have stale format info from previous sessions
    audioEngine.reset()

    // Get the ACTUAL hardware sample rate from the audio session
    // This is more reliable than inputNode.outputFormat() for Bluetooth HFP
    let session = AVAudioSession.sharedInstance()
    let hardwareSampleRate = session.sampleRate
    NSLog("[Audio] Hardware sample rate from session: %.0f Hz", hardwareSampleRate)

    audioEngine.attach(playerNode)
    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

    let inputNode = audioEngine.inputNode

    // Create input format matching the actual hardware sample rate
    // This is critical for Bluetooth HFP which may use 8/16/24kHz
    let inputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: hardwareSampleRate,
      channels: 1,
      interleaved: false
    )!

    NSLog("[Audio] Using input format: %.0f Hz (from audio session)", hardwareSampleRate)

    sendQueue.async { self.accumulatedData = Data() }

    // Target format for Gemini (16kHz mono)
    let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.inputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!

    // We'll create converters on-demand based on actual buffer format
    // This handles dynamic format changes when Bluetooth connects/disconnects
    var currentConverter: AVAudioConverter?
    var currentInputFormat: AVAudioFormat?
    var tapCount = 0

    // Use the format matching actual hardware sample rate
    // This prevents format mismatch crashes with Bluetooth HFP
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
      guard let self else { return }

      tapCount += 1
      let bufferFormat = buffer.format
      let pcmData: Data

      // Check if we need to resample (format differs from target 16kHz)
      let needsConversion = bufferFormat.sampleRate != GeminiConfig.inputAudioSampleRate
          || bufferFormat.channelCount != GeminiConfig.audioChannels

      if needsConversion {
        // Create or update converter if format changed
        if currentInputFormat == nil || !bufferFormat.isEqual(currentInputFormat!) {
          currentInputFormat = bufferFormat
          currentConverter = AVAudioConverter(from: bufferFormat, to: targetFormat)
          if tapCount <= 5 {
            NSLog("[Audio] Created converter: %.0fHz ch=%d -> %.0fHz ch=%d",
                  bufferFormat.sampleRate, bufferFormat.channelCount,
                  targetFormat.sampleRate, targetFormat.channelCount)
          }
        }

        guard let converter = currentConverter,
              let resampled = self.convertBuffer(buffer, using: converter, targetFormat: targetFormat) else {
          if tapCount <= 3 { NSLog("[Audio] Resample failed for tap #%d", tapCount) }
          return
        }
        pcmData = self.float32BufferToInt16Data(resampled)
      } else {
        pcmData = self.float32BufferToInt16Data(buffer)
      }

      // Accumulate into ~100ms chunks before sending to Gemini
      self.sendQueue.async {
        self.accumulatedData.append(pcmData)
        if self.accumulatedData.count >= self.minSendBytes {
          let chunk = self.accumulatedData
          self.accumulatedData = Data()
          if tapCount <= 3 {
            NSLog("[Audio] Sending chunk: %d bytes (~%dms)",
                  chunk.count, chunk.count / 32)  // 16kHz * 2 bytes = 32 bytes/ms
          }
          self.onAudioCaptured?(chunk)
        }
      }
    }

    try audioEngine.start()
    playerNode.play()
    isCapturing = true
  }

  func playAudio(data: Data) {
    guard isCapturing, !data.isEmpty else { return }

    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!

    let frameCount = UInt32(data.count) / (GeminiConfig.audioBitsPerSample / 8 * GeminiConfig.audioChannels)
    guard frameCount > 0 else { return }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frameCount) else { return }
    buffer.frameLength = frameCount

    guard let floatData = buffer.floatChannelData else { return }
    data.withUnsafeBytes { rawBuffer in
      guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
      for i in 0..<Int(frameCount) {
        floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
      }
    }

    playerNode.scheduleBuffer(buffer)
    if !playerNode.isPlaying {
      playerNode.play()
    }
  }

  func stopPlayback() {
    playerNode.stop()
    playerNode.play()
  }

  func stopCapture() {
    guard isCapturing else { return }
    NSLog("[Audio] Stopping capture...")

    // Remove tap first to stop receiving audio callbacks
    audioEngine.inputNode.removeTap(onBus: 0)

    playerNode.stop()
    audioEngine.stop()

    // Detach player node safely
    if audioEngine.attachedNodes.contains(playerNode) {
      audioEngine.detach(playerNode)
    }

    isCapturing = false
    isPaused = false

    // Flush any remaining accumulated audio
    sendQueue.async {
      if !self.accumulatedData.isEmpty {
        let chunk = self.accumulatedData
        self.accumulatedData = Data()
        self.onAudioCaptured?(chunk)
      }
    }
    NSLog("[Audio] Capture stopped")
  }

  // MARK: - Private helpers

  private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0, let floatData = buffer.floatChannelData else { return 0 }
    var sumSquares: Float = 0
    for i in 0..<frameCount {
      let s = floatData[0][i]
      sumSquares += s * s
    }
    return sqrt(sumSquares / Float(frameCount))
  }

  private func float32BufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0, let floatData = buffer.floatChannelData else { return Data() }
    var int16Array = [Int16](repeating: 0, count: frameCount)
    for i in 0..<frameCount {
      let sample = max(-1.0, min(1.0, floatData[0][i]))
      int16Array[i] = Int16(sample * Float(Int16.max))
    }
    return int16Array.withUnsafeBufferPointer { ptr in
      Data(buffer: ptr)
    }
  }

  private func convertBuffer(
    _ inputBuffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    targetFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
    let outputFrameCount = UInt32(Double(inputBuffer.frameLength) * ratio)
    guard outputFrameCount > 0 else { return nil }

    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
      return nil
    }

    var error: NSError?
    var consumed = false
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return inputBuffer
    }

    if error != nil {
      return nil
    }

    return outputBuffer
  }
}
