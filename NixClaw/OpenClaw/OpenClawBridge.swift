import Foundation
import UIKit

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle

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

    let messageContent: Any
    if let image = image {
      NSLog("[OpenClaw] Image exists, attempting JPEG encoding...")
      if let jpegData = image.jpegData(compressionQuality: 0.8) {
        // Multimodal message with image
        let base64Image = jpegData.base64EncodedString()
        NSLog("[OpenClaw] JPEG encoding SUCCESS. Size: %d bytes, base64 length: %d", jpegData.count, base64Image.count)
        messageContent = [
          [
            "type": "image_url",
            "image_url": [
              "url": "data:image/jpeg;base64,\(base64Image)"
            ]
          ],
          [
            "type": "text",
            "text": task
          ]
        ]
      } else {
        NSLog("[OpenClaw] ERROR: JPEG encoding FAILED!")
        messageContent = task
      }
    } else {
      NSLog("[OpenClaw] No image provided, sending text-only message")
      // Text-only message
      messageContent = task
    }

    let body: [String: Any] = [
      "model": "openclaw",
      "messages": [
        ["role": "user", "content": messageContent]
      ],
      "stream": false
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
