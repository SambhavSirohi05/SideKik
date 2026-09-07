import SwiftUI

/// Settings and Configuration view for API keys, voices, and permissions
public struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    public var onBack: (() -> Void)?

    @State private var geminiKeyInput: String = ""
    @State private var sarvamKeyInput: String = ""
    @State private var saveMessage: String? = nil

    public init(onBack: (() -> Void)? = nil) {
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Navigation Bar
            HStack {
                if let onBack = onBack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("Settings")
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                // Balancing spacer
                if onBack != nil {
                    Text("     ")
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Gemini Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Gemini API Key")
                            .font(.system(size: 12, weight: .semibold))
                        SecureField("Paste AI Studio API Key...", text: $geminiKeyInput)
                            .textFieldStyle(.roundedBorder)

                        Text("Free tier via Google AI Studio (1500 req/day).")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Sarvam Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sarvam AI API Key")
                            .font(.system(size: 12, weight: .semibold))
                        SecureField("Paste Sarvam API Key...", text: $sarvamKeyInput)
                            .textFieldStyle(.roundedBorder)

                        Text("Powers low-latency Saaras v4 STT & Bulbul v3 TTS.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Voice Character Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sarvam Voice Character")
                            .font(.system(size: 12, weight: .semibold))
                        Picker("", selection: $state.selectedVoice) {
                            Text("Shubh (Male)").tag("shubh")
                            Text("Priya (Female)").tag("priya")
                            Text("Ritu (Female)").tag("ritu")
                            Text("Neerja (Female)").tag("neerja")
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Text("Pace: \(String(format: "%.2fx", state.speechPace))")
                                .font(.system(size: 11))
                            Slider(value: $state.speechPace, in: 0.8...1.4, step: 0.05)
                        }
                    }

                    // Auto-Click Toggle
                    Toggle("Auto-Click Target Elements", isOn: $state.autoClick)
                        .font(.system(size: 12, weight: .medium))

                    Divider()

                    // Permissions Checklist
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Permissions")
                            .font(.system(size: 12, weight: .semibold))

                        permissionRow(
                            title: "Microphone",
                            status: permissions.hasMicrophone,
                            action: { permissions.requestMicrophone() }
                        )
                        permissionRow(
                            title: "Screen Recording",
                            status: permissions.hasScreenCapture,
                            action: { permissions.requestScreenCapture() }
                        )
                        permissionRow(
                            title: "Accessibility",
                            status: permissions.hasAccessibility,
                            action: { permissions.requestAccessibility() }
                        )
                    }

                    // Save Button
                    VStack(spacing: 4) {
                        Button(action: saveSettings) {
                            HStack {
                                Spacer()
                                Text("Save Settings")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        if let msg = saveMessage {
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(width: 320, height: 440)
        .onAppear {
            state.loadConfig()
            geminiKeyInput = state.geminiApiKey
            sarvamKeyInput = state.sarvamApiKey
            permissions.checkAllPermissions()
        }
    }

    private func permissionRow(title: String, status: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
            Spacer()
            if status {
                Text("Granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func saveSettings() {
        state.geminiApiKey = geminiKeyInput
        state.sarvamApiKey = sarvamKeyInput
        state.saveConfig()

        saveMessage = "Saved successfully!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            saveMessage = nil
        }
    }
}
