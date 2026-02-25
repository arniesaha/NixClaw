import Foundation
import UIKit

@MainActor
class ToolCallRouter {
  private let bridge: OpenClawBridge
  private var inFlightTasks: [String: Task<Void, Never>] = [:]

  // Keywords that indicate the tool call wants to include the current view/image
  private let imageKeywords = [
    "picture", "photo", "image", "see", "look", "view", "show",
    "what do you see", "what is this", "what's this", "identify",
    "describe", "camera", "screenshot", "capture", "snap"
  ]

  init(bridge: OpenClawBridge) {
    self.bridge = bridge
  }

  /// Route a tool call from Gemini to OpenClaw. Calls sendResponse with the
  /// JSON dictionary to send back as a toolResponse message.
  /// If currentFrame is provided and the task mentions images/photos, it will be included.
  func handleToolCall(
    _ call: GeminiFunctionCall,
    currentFrame: UIImage? = nil,
    sendResponse: @escaping ([String: Any]) -> Void
  ) {
    let callId = call.id
    let callName = call.name

    NSLog("[ToolCall] Received: %@ (id: %@) args: %@",
          callName, callId, String(describing: call.args))

    let task = Task { @MainActor in
      let taskDesc = call.args["task"] as? String ?? String(describing: call.args)

      // Check if this task wants an image included
      let taskWantsImage = self.taskNeedsImage(taskDesc)
      let hasFrame = currentFrame != nil
      let shouldIncludeImage = taskWantsImage && hasFrame
      let imageToSend = shouldIncludeImage ? currentFrame : nil

      NSLog("[ToolCall] taskWantsImage=%d, hasFrame=%d, shouldInclude=%d",
            taskWantsImage ? 1 : 0, hasFrame ? 1 : 0, shouldIncludeImage ? 1 : 0)

      if shouldIncludeImage {
        NSLog("[ToolCall] Including current video frame with task")
      } else if taskWantsImage && !hasFrame {
        NSLog("[ToolCall] WARNING: Task wants image but no frame available!")
      }

      let result = await bridge.delegateTask(task: taskDesc, toolName: callName, image: imageToSend)

      guard !Task.isCancelled else {
        NSLog("[ToolCall] Task %@ was cancelled, skipping response", callId)
        return
      }

      NSLog("[ToolCall] Result for %@ (id: %@): %@",
            callName, callId, String(describing: result))

      let response = self.buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)

      self.inFlightTasks.removeValue(forKey: callId)
    }

    inFlightTasks[callId] = task
  }

  /// Cancel specific in-flight tool calls (from toolCallCancellation)
  func cancelToolCalls(ids: [String]) {
    for id in ids {
      if let task = inFlightTasks[id] {
        NSLog("[ToolCall] Cancelling in-flight call: %@", id)
        task.cancel()
        inFlightTasks.removeValue(forKey: id)
      }
    }
    bridge.lastToolCallStatus = .cancelled(ids.first ?? "unknown")
  }

  /// Cancel all in-flight tool calls (on session stop)
  func cancelAll() {
    for (id, task) in inFlightTasks {
      NSLog("[ToolCall] Cancelling in-flight call: %@", id)
      task.cancel()
    }
    inFlightTasks.removeAll()
  }

  // MARK: - Private

  /// Check if the task description suggests the user wants to include an image
  private func taskNeedsImage(_ task: String) -> Bool {
    let lowercased = task.lowercased()
    return imageKeywords.contains { lowercased.contains($0) }
  }

  private func buildToolResponse(
    callId: String,
    name: String,
    result: ToolResult
  ) -> [String: Any] {
    return [
      "toolResponse": [
        "functionResponses": [
          [
            "id": callId,
            "name": name,
            "response": result.responseValue
          ]
        ]
      ]
    ]
  }
}
