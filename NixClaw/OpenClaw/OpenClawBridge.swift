import Foundation
import UIKit

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var debugImageReachedDelegateTask: Bool = false  // DEBUG: did image reach delegateTask?

  private let session: URLSession
  private var sessionKey: String
  
  // Upload server config
  private let uploadBaseURL: String
  private let uploadToken: String

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120
    self.session = URLSession(configuration: config)
    self.sessionKey = OpenClawBridge.newSessionKey()
    
    // Upload server on NAS (same host as OpenClaw gateway, different port)
    // Extract base URL from gateway URL and use upload port
    let gatewayURL = AppConfig.shared.openClawBaseURL
    if let url = URL(string: gatewayURL), let host = url.host {
      let scheme = url.scheme ?? "http"
      self.uploadBaseURL = "\(scheme)://\(host):18795"
    } else {
      self.uploadBaseURL = "http://arnabsnas.tailb3dd58.ts.net:18795"
    }
    self.uploadToken = "nixclaw-upload-secret"
    NSLog("[OpenClaw] Upload server: %@", uploadBaseURL)
  }

  func resetSession() {
    sessionKey = OpenClawBridge.newSessionKey()
    NSLog("[OpenClaw] New session: %@", sessionKey)
  }

  private static func newSessionKey() -> String {
    let ts = ISO8601DateFormatter().string(from: Date())
    return "agent:main:glass:\(ts)"
  }

  // MARK: - Image Upload
  
  /// Upload image to NAS, returns the file path on success
  private func uploadImage(_ image: UIImage) async -> String? {
    guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
      NSLog("[OpenClaw] Failed to encode image as JPEG")
      return nil
    }
    
    guard let url = URL(string: "\(uploadBaseURL)/upload") else {
      NSLog("[OpenClaw] Invalid upload URL")
      return nil
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(uploadToken)", forHTTPHeaderField: "Authorization")
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.httpBody = jpegData
    
    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode) else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        NSLog("[OpenClaw] Upload failed: HTTP %d", code)
        return nil
      }
      
      // Parse response: {"ok": true, "path": "/tmp/nixclaw/..."}
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let path = json["path"] as? String {
        NSLog("[OpenClaw] Image uploaded to: %@", path)
        return path
      }
      
      NSLog("[OpenClaw] Upload response missing path")
      return nil
    } catch {
      NSLog("[OpenClaw] Upload error: %@", error.localizedDescription)
      return nil
    }
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

    NSLog("[OpenClaw] delegateTask called. image param is: %@", image != nil ? "NOT NIL" : "NIL")
    await MainActor.run { self.debugImageReachedDelegateTask = (image != nil) }

    // Build the message - if image exists, upload it first and reference the path
    var finalTask = task
    
    if let image = image {
      NSLog("[OpenClaw] Uploading image to NAS...")
      if let imagePath = await uploadImage(image) {
        // Prepend image path instruction to the task
        finalTask = "First, analyze the image at \(imagePath) using the image tool. Then respond to: \(task)"
        NSLog("[OpenClaw] Message with image path: %@", String(finalTask.prefix(100)))
      } else {
        NSLog("[OpenClaw] Image upload failed, sending text-only")
      }
    }

    let body: [String: Any] = [
      "model": "openclaw",
      "messages": [
        ["role": "user", "content": finalTask]
      ],
      "stream": false
    ]

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: body)
      request.httpBody = jsonData
      
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[OpenClaw] Chat failed: HTTP %d - %@", code, String(bodyStr.prefix(200)))
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Chat request failed (HTTP \(code))")
      }

      // Parse OpenAI-style response
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any],
            let content = message["content"] as? String else {
        lastToolCallStatus = .failed(toolName, "Invalid response")
        return .failure("Could not parse response")
      }

      lastToolCallStatus = .completed(toolName)
      return .success(content)

    } catch {
      NSLog("[OpenClaw] Request error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Request error: \(error.localizedDescription)")
    }
  }
}
