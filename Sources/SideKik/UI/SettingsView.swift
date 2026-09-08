import SwiftUI

/// Premium Apple-native Settings view for API keys, voices, behaviors, and permissions
public struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    public var onBack: (() -> Void)?
    public var showNavigationHeader: Bool

    @State private var geminiKeyInput: String = ""
    @State private var sarvamKeyInput: String = ""
    @State private var saveMessage: String? = nil

    public init(onBack: (() -> Void)? = nil, showNavigationHeader: Bool = false) {
        self.onBack = onBack
        self.showNavigationHeader = showNavigationHeader
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showNavigationHeader {
                // Navigation Bar for standalone presentation
                HStack {
                    if let onBack = onBack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text("Preferences")
                        .font(.system(size: 13, weight: .bold))

                    Spacer()

                    if onBack != nil {
                        Text("     ").font(.system(size: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
            }

            ScrollView {
                VStack(spacing: 16) {
                    // 1. AI Reasoning Section (Google Gemini)
                    settingsSectionCard(title: "AI Reasoning & Vision", icon: "sparkles") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Google Gemini API Key")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                if !state.geminiApiKey.isEmpty {
                                    statusBadge(text: "Active", isGreen: true)
                                } else {
                                    statusBadge(text: "Required for Vision", isGreen: false)
                                }
                            }

                            SecureField("Paste AI Studio API Key...", text: $geminiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

                            Text("Free tier via Google AI Studio (1,500 req/day). Used for screen vision and multimodal reasoning.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // 2. Audio & Speech Section (Sarvam AI)
                    settingsSectionCard(title: "Voice & Speech", icon: "waveform") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Sarvam AI API Key")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                if !state.sarvamApiKey.isEmpty {
                                    statusBadge(text: "Active", isGreen: true)
                                } else {
                                    statusBadge(text: "Voice Key", isGreen: false)
                                }
                            }

                            SecureField("Paste Sarvam API Key...", text: $sarvamKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

                            Divider().padding(.vertical, 2)

                            HStack {
                                Text("Voice Character")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Picker("", selection: $state.selectedVoice) {
                                    Text("Shubh (Male • Friendly)").tag("shubh")
                                    Text("Priya (Female • Crisp)").tag("priya")
                                    Text("Ritu (Female • Warm)").tag("ritu")
                                    Text("Neerja (Female • Natural)").tag("neerja")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 170)
                            }

                            HStack {
                                Text("Speech Pace")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text(String(format: "%.2fx", state.speechPace))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: $state.speechPace, in: 0.8...1.4, step: 0.05)
                                .tint(.accentColor)
                        }
                    }

                    // 3. Behavior & Automation Section
                    settingsSectionCard(title: "Behavior & Automation", icon: "slider.horizontal.3") {
                        VStack(spacing: 10) {
                            Toggle(isOn: $state.isPetEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Show On-Screen Companion Avatar")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Renders the animated OpenPets companion sprite on the desktop.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)

                            Divider().padding(.vertical, 2)

                            Toggle(isOn: $state.autoClick) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-Click On Target Elements")
                                        .font(.system(size: 11, weight: .medium))
                                    Text("Automatically clicks recognized buttons without prompting.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }

                    // 4. System Permissions Checklist
                    settingsSectionCard(title: "System Permissions", icon: "lock.shield") {
                        VStack(spacing: 8) {
                            permissionRow(
                                title: "Microphone",
                                subtitle: "Push-to-talk speech recognition",
                                status: permissions.hasMicrophone,
                                action: { permissions.requestMicrophone() }
                            )

                            Divider().padding(.vertical, 1)

                            permissionRow(
                                title: "Screen Recording",
                                subtitle: "Multimodal desktop reasoning",
                                status: permissions.hasScreenCapture,
                                action: { permissions.requestScreenCapture() }
                            )

                            Divider().padding(.vertical, 1)

                            permissionRow(
                                title: "Accessibility",
                                subtitle: "Cursor guidance & simulated clicks",
                                status: permissions.hasAccessibility,
                                action: { permissions.requestAccessibility() }
                            )
                        }
                    }

                    // Save Button
                    VStack(spacing: 8) {
                        Button(action: saveSettings) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                Text("Save Settings")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        if let msg = saveMessage {
                            Text(msg)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .onAppear {
            state.loadConfig()
            geminiKeyInput = state.geminiApiKey
            sarvamKeyInput = state.sarvamApiKey
            permissions.checkAllPermissions()
        }
    }

    private func settingsSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 1)
            )
        }
    }

    private func statusBadge(text: String, isGreen: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isGreen ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isGreen ? .green : .orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isGreen ? Color.green : Color.orange).opacity(0.12))
        .cornerRadius(4)
    }

    private func permissionRow(title: String, subtitle: String, status: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if status {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Granted")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12))
                .cornerRadius(6)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func saveSettings() {
        state.geminiApiKey = geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        state.sarvamApiKey = sarvamKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        state.saveConfig()

        withAnimation {
            saveMessage = "Preferences saved successfully!"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                saveMessage = nil
            }
        }
    }
}
