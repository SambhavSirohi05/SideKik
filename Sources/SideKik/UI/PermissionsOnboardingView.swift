import SwiftUI
import AppKit

/// Dedicated initial permissions onboarding window displayed on first launch
public struct PermissionsOnboardingView: View {
    @ObservedObject private var permissions = PermissionsManager.shared
    @ObservedObject private var state = AppState.shared
    public var onComplete: () -> Void

    @State private var timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    private var allGranted: Bool {
        permissions.hasMicrophone && permissions.hasScreenCapture && permissions.hasAccessibility
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header with animated Pet
            VStack(spacing: 8) {
                PetSpriteRenderer(pet: PetIdentity.find(byId: state.selectedPetId), state: .happy, size: 64)

                Text("Welcome to SideKik")
                    .font(.system(size: 22, weight: .bold))

                Text("Your zero-toll, ambient desktop companion. To see, listen, and guide you, SideKik requires a few standard macOS permissions:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)

            // Permissions Checklist Cards
            VStack(spacing: 12) {
                // Microphone
                permissionCard(
                    icon: "mic.fill",
                    iconColor: .blue,
                    title: "Microphone Access",
                    description: "Captures your voice strictly while holding Control + Option for push-to-talk.",
                    isGranted: permissions.hasMicrophone,
                    action: { permissions.requestMicrophone() }
                )

                // Screen Recording
                permissionCard(
                    icon: "display",
                    iconColor: .purple,
                    title: "Screen Recording",
                    description: "Grabs instant in-memory display frames via ScreenCaptureKit (<15ms, never saved to disk).",
                    isGranted: permissions.hasScreenCapture,
                    action: { permissions.requestScreenCapture() }
                )

                // Accessibility
                permissionCard(
                    icon: "accessibility",
                    iconColor: .orange,
                    title: "Accessibility",
                    description: "Allows SideKik to inspect active windows and point to interface controls.",
                    isGranted: permissions.hasAccessibility,
                    action: { permissions.requestAccessibility() }
                )
            }
            .padding(.horizontal, 24)

            Divider()
                .padding(.horizontal, 24)

            // Action Footer
            HStack {
                Button("I'll do this later") {
                    onComplete()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

                Spacer()

                Button(action: onComplete) {
                    HStack {
                        Text(allGranted ? "Get Started 🎉" : "Continue")
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(allGranted ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(timer) { _ in
            permissions.checkAllPermissions()
        }
    }

    private func permissionCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Allowed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                Button("Grant Access", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isGranted ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
}
