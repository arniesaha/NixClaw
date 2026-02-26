import Foundation
import UIKit

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var debugImageReachedDelegateTask: Bool = false  // DEBUG: did image reach delegateTask?

  private let session: URLSession
  private var sessionKey: String

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120
    self.session = URLSession(configuration: config)
    self.sessionKey = OpenClawBridge.newSessionKey()
  }

  func resetSession() {
    sessionKey = OpenClawBridge.newSessionKey()
    NSLog("[OpenClaw] New session: %@", sessionKey)
  }

  private static func newSessionKey() -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    return "agent:main:glass:\(ts)"
  }

  // MARK: - Agent Chat (session continuity via x-openclaw-session-key header)

  func delegateTask(
    task: String,
    toolName: String = "execute",
    image: UIImage? = nil
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)

    guard let url = URL(string: "\(AppConfig.shared.openClawBaseURL)/v1/chat/completions") else {
      lastToolCallStatus = .failed(toolName, "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(AppConfig.shared.openClawToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")

    // Build message content - text only or multimodal with image
    NSLog("[OpenClaw] delegateTask called. image param is: %@", image != nil ? "NOT NIL" : "NIL")

    // DEBUG: Update published property so UI can show it
    await MainActor.run { self.debugImageReachedDelegateTask = (image != nil) }

    var messageContent: Any = task
    var savedImagePath: String? = nil

    if let image = image {
      NSLog("[OpenClaw] Image exists, attempting to save to file...")
      if let jpegData = image.jpegData(compressionQuality: 0.8) {
        // Save image to temp file and include path in message
        let fileName = "nixclaw_\(UUID().uuidString).jpg"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
          try jpegData.write(to: fileURL)
          savedImagePath = fileURL.path
          NSLog("[OpenClaw] Image saved to: %@", fileURL.path)

          // Use OpenAI Vision API format (OpenClaw gateway expects this)
          let base64Image = jpegData.base64EncodedString()
          let dataUrl = "data:image/jpeg;base64,\(base64Image)"
          messageContent = [
            [
              "type": "image_url",
              "image_url": [
                "url": dataUrl
              ] as [String: Any]
            ] as [String: Any],
            [
              "type": "text",
              "text": task
            ] as [String: Any]
          ]
        } catch {
          NSLog("[OpenClaw] ERROR saving image: %@", error.localizedDescription)
          messageContent = task
        }
      } else {
        NSLog("[OpenClaw] ERROR: JPEG encoding FAILED!")
      }
    } else {
      NSLog("[OpenClaw] No image provided, sending text-only message")
    }

    let body: [String: Any] = [
      "model": "openclaw",
      "messages": [
        ["role": "user", "content": messageContent]
      ],
      "stream": false
    ]

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: body)

      // DEBUG: Log the JSON structure (truncated)
      if let jsonStr = String(data: jsonData, encoding: .utf8) {
        let preview = String(jsonStr.prefix(500))
        NSLog("[OpenClaw] Request JSON preview: %@", preview)
        // Check if image is in the JSON (OpenAI format uses image_url)
        if jsonStr.contains("\"type\":\"image_url\"") || jsonStr.contains("\"type\": \"image_url\"") {
          NSLog("[OpenClaw] ✓ Image content IS in JSON (OpenAI format)")
        } else if jsonStr.contains("data:image") {
          NSLog("[OpenClaw] ✓ Image data URL found in JSON")
        } else {
          NSLog("[OpenClaw] ✗ Image content NOT in JSON!")
        }
      }

      request.httpBody = jsonData
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[OpenClaw] Chat failed: HTTP %d - %@", code, String(bodyStr.prefix(200)))
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Agent returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        NSLog("[OpenClaw] Agent result: %@", String(content.prefix(200)))
        lastToolCallStatus = .completed(toolName)
        return .success(content)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      NSLog("[OpenClaw] Agent raw: %@", String(raw.prefix(200)))
      lastToolCallStatus = .completed(toolName)
      return .success(raw)
    } catch {
      NSLog("[OpenClaw] Agent error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Agent error: \(error.localizedDescription)")
    }
  }
}
