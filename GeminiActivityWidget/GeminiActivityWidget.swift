import ActivityKit
import SwiftUI
import WidgetKit

// Shared ActivityAttributes - must match the main app's definition exactly
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

struct GeminiActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GeminiSessionAttributes.self) { context in
      // Lock screen / banner UI
      GeminiLockScreenView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        // Expanded UI
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "waveform")
            .foregroundColor(context.state.isModelSpeaking ? .green : .white)
            .font(.title2)
        }

        DynamicIslandExpandedRegion(.trailing) {
          Text(formatDuration(context.state.sessionDuration))
            .font(.caption)
            .monospacedDigit()
            .foregroundColor(.secondary)
        }

        DynamicIslandExpandedRegion(.center) {
          Text(context.state.statusText)
            .font(.headline)
            .foregroundColor(.white)
        }

        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Circle()
              .fill(context.state.isConnected ? Color.green : Color.orange)
              .frame(width: 8, height: 8)
            Text(context.state.isConnected ? "Connected" : "Reconnecting")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
      } compactLeading: {
        // Compact leading - mic icon
        Image(systemName: context.state.isModelSpeaking ? "waveform" : "mic.fill")
          .foregroundColor(context.state.isModelSpeaking ? .green : .white)
      } compactTrailing: {
        // Compact trailing - duration
        Text(formatDuration(context.state.sessionDuration))
          .font(.caption2)
          .monospacedDigit()
      } minimal: {
        // Minimal - just mic icon
        Image(systemName: "mic.fill")
          .foregroundColor(context.state.isConnected ? .green : .orange)
      }
    }
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

struct GeminiLockScreenView: View {
  let context: ActivityViewContext<GeminiSessionAttributes>

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: context.state.isModelSpeaking ? "waveform" : "mic.fill")
        .font(.title2)
        .foregroundColor(context.state.isModelSpeaking ? .green : .white)
        .frame(width: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(context.attributes.assistantName)
          .font(.headline)
          .foregroundColor(.white)
        Text(context.state.statusText)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 2) {
        Text(formatDuration(context.state.sessionDuration))
          .font(.title3)
          .monospacedDigit()
          .foregroundColor(.white)
        HStack(spacing: 4) {
          Circle()
            .fill(context.state.isConnected ? Color.green : Color.orange)
            .frame(width: 6, height: 6)
          Text(context.state.isConnected ? "Live" : "...")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
    }
    .padding()
    .background(Color.black.opacity(0.8))
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
