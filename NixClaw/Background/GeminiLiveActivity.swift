import ActivityKit
import Foundation

struct GeminiSessionAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var isConnected: Bool
    var isModelSpeaking: Bool
    var sessionDuration: TimeInterval
    var statusText: String
  }

  var sessionId: String
  var startTime: Date
  var assistantName: String
}

@MainActor
class GeminiLiveActivityManager: ObservableObject {
  static let shared = GeminiLiveActivityManager()

  private var currentActivity: Activity<GeminiSessionAttributes>?

  private init() {}

  func startActivity() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      NSLog("[LiveActivity] Activities not enabled")
      return
    }

    // End any existing activity
    endActivity()

    let attributes = GeminiSessionAttributes(
      sessionId: UUID().uuidString,
      startTime: Date(),
      assistantName: AppConfig.shared.assistantName
    )

    let initialState = GeminiSessionAttributes.ContentState(
      isConnected: true,
      isModelSpeaking: false,
      sessionDuration: 0,
      statusText: "Listening..."
    )

    do {
      let activity = try Activity.request(
        attributes: attributes,
        content: .init(state: initialState, staleDate: nil),
        pushType: nil
      )
      currentActivity = activity
      NSLog("[LiveActivity] Started activity: %@", activity.id)
    } catch {
      NSLog("[LiveActivity] Failed to start: %@", error.localizedDescription)
    }
  }

  func updateActivity(isConnected: Bool, isModelSpeaking: Bool, duration: TimeInterval) {
    guard let activity = currentActivity else { return }

    let statusText: String
    if !isConnected {
      statusText = "Reconnecting..."
    } else if isModelSpeaking {
      statusText = "Speaking..."
    } else {
      statusText = "Listening..."
    }

    let updatedState = GeminiSessionAttributes.ContentState(
      isConnected: isConnected,
      isModelSpeaking: isModelSpeaking,
      sessionDuration: duration,
      statusText: statusText
    )

    Task {
      await activity.update(.init(state: updatedState, staleDate: nil))
    }
  }

  func endActivity() {
    guard let activity = currentActivity else { return }

    let finalState = GeminiSessionAttributes.ContentState(
      isConnected: false,
      isModelSpeaking: false,
      sessionDuration: 0,
      statusText: "Session ended"
    )

    Task {
      await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
      NSLog("[LiveActivity] Ended activity")
    }

    currentActivity = nil
  }
}
