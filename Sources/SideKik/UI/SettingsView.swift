import SwiftUI

/// Settings and Configuration view for API keys, voices, and permissions
public struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    @State private var geminiKeyInput: String = ""
    @State private var sarvamKeyInput: String = ""
    @State private var saveMessage: String? = nil

    public init() {}

    public var body: some View {
        Form {
            Section(header: Text("AI Reasoning & Vision")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Google Gemini API Key (Free Lifetime Tier)")
                        .font(.system(size: 12, weight: .semibold))
                    SecureField("Paste AI Studio API Key...", text: $geminiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Text("Used for high-precision multimodal screen reasoning with zero laptop load.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Link("Get Free Google AI Studio Key ↗", destination: URL(string: "https://aistudio.google.com/")!)
                    .font(.system(size: 11))
            }

            Section(header: Text("Speech & Acoustic Synthesis")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sarvam AI API Key (Optional)")
                        .font(.system(size: 12, weight: .semibold))
                    SecureField("Paste Sarvam API Key...", text: $sarvamKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Text("For low-latency Saaras v4 STT & Bulbul v3 TTS. If blank, native Apple Siri/Samantha voice is used 100% free.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Toggle("Always use macOS Native Voice (Zero Cost)", isOn: $state.useLocalSpeechFallback)

                Picker("Voice Character", selection: $state.selectedVoice) {
                    Text("Shubh (Male)").tag("shubh")
                    Text("Priya (Female)").tag("priya")
                    Text("Ritu (Female)").tag("ritu")
                    Text("Neerja (Female)").tag("neerja")
                }

                HStack {
                    Text("Speech Pace: \(String(format: "%.2fx", state.speechPace))")
                    Slider(value: $state.speechPace, in: 0.8...1.4, step: 0.05)
                }
            }

            Section(header: Text("System Permissions")) {
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

            Section {
                Button(action: saveSettings) {
                    HStack {
                        Spacer()
                        Text("Save & Apply Settings")
                            .bold()
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)

                if let msg = saveMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .frame(width: 420, height: 480)
        .onAppear {
            geminiKeyInput = state.geminiApiKey
            sarvamKeyInput = state.sarvamApiKey
            permissions.checkAllPermissions()
        }
    }

    private func permissionRow(title: String, status: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if status {
                Text("Granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
            } else {
                Button("Authorize", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func saveSettings() {
        state.geminiApiKey = geminiKeyInput
        state.sarvamApiKey = sarvamKeyInput
        KeychainHelper.shared.save(key: "gemini_api_key", value: geminiKeyInput)
        KeychainHelper.shared.save(key: "sarvam_api_key", value: sarvamKeyInput)

        saveMessage = "Settings saved securely to Keychain!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            saveMessage = nil
        }
    }
}
