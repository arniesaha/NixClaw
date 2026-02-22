import SwiftUI

struct SetupWizardView: View {
  @EnvironmentObject private var appConfig: AppConfig

  @State private var step = 1

  // Step 1 — Gemini
  @State private var geminiKey = ""

  // Step 2 — OpenClaw
  @State private var openClawHostname = ""
  @State private var openClawPort = "18789"
  @State private var openClawToken = ""

  // Step 3 — Personalization
  @State private var assistantName = ""
  @State private var accentHex = "007AFF"

  private let presetColors: [(name: String, hex: String)] = [
    ("Blue",   "007AFF"),
    ("Purple", "7C3AED"),
    ("Green",  "10B981"),
    ("Orange", "F59E0B"),
    ("Red",    "EF4444"),
    ("Pink",   "EC4899"),
  ]

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Progress indicator
        HStack(spacing: 8) {
          ForEach(1...3, id: \.self) { i in
            Capsule()
              .fill(i <= step ? Color(hex: accentHex) ?? .blue : Color.secondary.opacity(0.3))
              .frame(height: 4)
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)

        switch step {
        case 1:  stepGemini
        case 2:  stepOpenClaw
        default: stepPersonalization
        }
      }
      .navigationTitle("Setup")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  // MARK: - Step 1: Gemini API Key

  private var stepGemini: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Welcome to \(appConfig.appName)")
            .font(.title).bold()
          Text("To get started, enter your Gemini API key. This is required for voice conversations.")
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Gemini API Key")
            .font(.headline)
          SecureField("AIzaSy...", text: $geminiKey)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Link("Get a free key at Google AI Studio →",
               destination: URL(string: "https://aistudio.google.com/apikey")!)
            .font(.caption)
        }

        Spacer(minLength: 32)

        Button {
          step = 2
        } label: {
          Text("Next")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(hex: accentHex) ?? .blue)
        .disabled(geminiKey.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(24)
    }
  }

  // MARK: - Step 2: OpenClaw (optional)

  private var stepOpenClaw: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          Text("OpenClaw Gateway")
            .font(.title).bold()
          Text("Optional. OpenClaw lets the assistant perform actions — send messages, search the web, control apps — via a gateway running on your Mac.")
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 12) {
          labeledField("Hostname", placeholder: "192.168.1.x or myhost.local", text: $openClawHostname)
          labeledField("Port", placeholder: "18789", text: $openClawPort)
            .keyboardType(.numberPad)
          VStack(alignment: .leading, spacing: 4) {
            Text("Token").font(.subheadline).foregroundStyle(.secondary)
            SecureField("Gateway token", text: $openClawToken)
              .textFieldStyle(.roundedBorder)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
        }

        HStack(spacing: 12) {
          Button("Skip") {
            step = 3
          }
          .buttonStyle(.bordered)
          .frame(maxWidth: .infinity)

          Button("Next") {
            step = 3
          }
          .buttonStyle(.borderedProminent)
          .tint(Color(hex: accentHex) ?? .blue)
          .frame(maxWidth: .infinity)
        }
      }
      .padding(24)
    }
  }

  // MARK: - Step 3: Personalization

  private var stepPersonalization: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Personalize")
            .font(.title).bold()
          Text("Give the assistant a name and choose an accent color.")
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 12) {
          labeledField("Assistant Name", placeholder: appConfig.appName, text: $assistantName)

          VStack(alignment: .leading, spacing: 8) {
            Text("Accent Color").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
              ForEach(presetColors, id: \.hex) { preset in
                Circle()
                  .fill(Color(hex: preset.hex) ?? .blue)
                  .frame(width: 32, height: 32)
                  .overlay(
                    Circle().strokeBorder(Color.white, lineWidth: accentHex == preset.hex ? 3 : 0)
                  )
                  .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                  .onTapGesture { accentHex = preset.hex }
              }
            }
          }
        }

        // Summary
        GroupBox("Ready to go") {
          VStack(alignment: .leading, spacing: 6) {
            summaryRow("Gemini API", value: "Configured ✓", color: .green)
            summaryRow("OpenClaw", value: openClawHostname.isEmpty ? "Skipped" : "Configured ✓",
                       color: openClawHostname.isEmpty ? .secondary : .green)
            summaryRow("Assistant name",
                       value: assistantName.isEmpty ? appConfig.appName : assistantName)
          }
        }

        Button("Get Started") {
          save()
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(hex: accentHex) ?? .blue)
        .frame(maxWidth: .infinity)
      }
      .padding(24)
    }
  }

  // MARK: - Helpers

  @ViewBuilder
  private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.subheadline).foregroundStyle(.secondary)
      TextField(placeholder, text: text)
        .textFieldStyle(.roundedBorder)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
  }

  @ViewBuilder
  private func summaryRow(_ label: String, value: String, color: Color = .primary) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).foregroundStyle(color)
    }
    .font(.subheadline)
  }

  private func save() {
    appConfig.geminiApiKey = geminiKey.trimmingCharacters(in: .whitespaces)

    if !openClawHostname.isEmpty {
      appConfig.openClawHostname = openClawHostname
      appConfig.openClawPort = Int(openClawPort) ?? 18789
      appConfig.openClawToken = openClawToken
      appConfig.openClawScheme = "http"
    }

    let name = assistantName.trimmingCharacters(in: .whitespaces)
    if !name.isEmpty {
      appConfig.assistantName = name
    }
    appConfig.accentColorHex = accentHex
  }
}

#Preview {
  SetupWizardView()
    .environmentObject(AppConfig.shared)
}
