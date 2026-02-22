import SwiftUI
#if DEBUG
import MWDATMockDevice
#endif

struct SettingsView: View {
  @EnvironmentObject private var appConfig: AppConfig
  @Environment(\.dismiss) private var dismiss
  #if DEBUG
  @EnvironmentObject private var debugMenuViewModel: DebugMenuViewModel
  #endif

  @State private var showResetConfirmation = false

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
      Form {
        appSection
        personalizationSection
        geminiSection
        openClawSection
        #if DEBUG
        developerSection
        #endif
        resetSection
        aboutSection
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .confirmationDialog(
        "Reset all settings to their defaults?",
        isPresented: $showResetConfirmation,
        titleVisibility: .visible
      ) {
        Button("Reset", role: .destructive) { appConfig.resetToDefaults() }
        Button("Cancel", role: .cancel) {}
      }
    }
  }

  // MARK: - Sections

  private var appSection: some View {
    Section("App") {
      LabeledContent("Name", value: appConfig.appName)
      LabeledContent("Version", value: appVersion)
    }
  }

  private var personalizationSection: some View {
    Section("Personalization") {
      HStack {
        Text("Assistant Name")
        Spacer()
        TextField(appConfig.appName, text: $appConfig.assistantName)
          .multilineTextAlignment(.trailing)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Accent Color")
        HStack(spacing: 14) {
          ForEach(presetColors, id: \.hex) { preset in
            Circle()
              .fill(Color(hex: preset.hex) ?? .blue)
              .frame(width: 28, height: 28)
              .overlay(
                Circle().strokeBorder(Color.primary, lineWidth: appConfig.accentColorHex == preset.hex ? 2.5 : 0)
              )
              .onTapGesture { appConfig.accentColorHex = preset.hex }
          }
        }
      }
    }
  }

  private var geminiSection: some View {
    Section {
      HStack {
        Text("API Key")
        Spacer()
        SecureField("Required", text: $appConfig.geminiApiKey)
          .multilineTextAlignment(.trailing)
          .foregroundStyle(.secondary)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      HStack {
        Text("Status")
        Spacer()
        Label(
          appConfig.isGeminiConfigured ? "Configured" : "Not configured",
          systemImage: appConfig.isGeminiConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )
        .foregroundStyle(appConfig.isGeminiConfigured ? .green : .orange)
        .font(.subheadline)
      }
      Link("Get an API key at Google AI Studio →",
           destination: URL(string: "https://aistudio.google.com/apikey")!)
        .font(.subheadline)
    } header: {
      Text("Gemini API")
    }
  }

  private var openClawSection: some View {
    Section {
      HStack {
        Text("Hostname")
        Spacer()
        TextField("192.168.x.x", text: $appConfig.openClawHostname)
          .multilineTextAlignment(.trailing)
          .foregroundStyle(.secondary)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      HStack {
        Text("Port")
        Spacer()
        TextField("18789", value: $appConfig.openClawPort, format: .number)
          .multilineTextAlignment(.trailing)
          .foregroundStyle(.secondary)
          .keyboardType(.numberPad)
      }
      HStack {
        Text("Token")
        Spacer()
        SecureField("Gateway token", text: $appConfig.openClawToken)
          .multilineTextAlignment(.trailing)
          .foregroundStyle(.secondary)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      HStack {
        Text("Status")
        Spacer()
        Label(
          appConfig.isOpenClawConfigured ? "Configured" : "Not configured",
          systemImage: appConfig.isOpenClawConfigured ? "checkmark.circle.fill" : "minus.circle"
        )
        .foregroundStyle(appConfig.isOpenClawConfigured ? .green : .secondary)
        .font(.subheadline)
      }
    } header: {
      Text("OpenClaw")
    } footer: {
      Text("Optional. Enables the assistant to perform actions via a gateway on your Mac.")
    }
  }

  private var resetSection: some View {
    Section {
      Button("Reset All Settings", role: .destructive) {
        showResetConfirmation = true
      }
    } footer: {
      Text("Returns all settings to their build-time defaults.")
    }
  }

  private var aboutSection: some View {
    Section("About") {
      Link("GitHub →", destination: URL(string: "https://github.com/arniesaha/NixClaw")!)
      Link("Report an issue →", destination: URL(string: "https://github.com/arniesaha/NixClaw/issues")!)
    }
  }

  #if DEBUG
  private var developerSection: some View {
    Section {
      Button {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          debugMenuViewModel.showDebugMenu = true
        }
      } label: {
        HStack {
          Label("Mock Device Kit", systemImage: "ladybug.fill")
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } header: {
      Text("Developer")
    } footer: {
      Text("Simulate Meta Ray-Ban glasses connections for testing.")
    }
  }
  #endif

  // MARK: - Helpers

  private var appVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    return build.isEmpty ? version : "\(version) (\(build))"
  }
}

#Preview {
  SettingsView()
    .environmentObject(AppConfig.shared)
}
