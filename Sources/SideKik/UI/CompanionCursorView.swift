import SwiftUI
import AppKit

/// Renders the companion pet avatar, Bézier glide animation, beacon highlight rings, and glassmorphic speech bubbles
public struct CompanionCursorView: View {
    @ObservedObject private var state = AppState.shared

    @State private var petPosition: CGPoint = CGPoint(x: 300, y: 300)
    @State private var beaconScale: CGFloat = 1.0
    @State private var beaconOpacity: Double = 0.8
    @State private var timer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()

    private var activePet: PetIdentity {
        PetIdentity.find(byId: state.selectedPetId)
    }

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Pulsing Target Beacon Rings (when pointing at a UI element)
                if let target = state.targetPoint {
                    targetBeaconView(at: target)
                }

                // 2. Animated Companion Pet Avatar
                companionAvatarView
                    .position(petPosition)

                // 3. Floating Speech & Alert Callout Bubble
                if shouldShowBubble {
                    floatingBubbleView
                        .position(x: petPosition.x + 130, y: max(60, petPosition.y - 70))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onReceive(timer) { _ in
                updateCompanionPosition(screenHeight: geometry.size.height)
            }
        }
    }

    // MARK: - Target Beacon Highlight
    private func targetBeaconView(at target: CGPoint) -> some View {
        ZStack {
            // Expanding outer ring
            Circle()
                .stroke(Color(hex: activePet.primaryColorHex), lineWidth: 3)
                .frame(width: 48 * beaconScale, height: 48 * beaconScale)
                .opacity(beaconOpacity)

            // Inner core dot
            Circle()
                .fill(Color(hex: activePet.primaryColorHex))
                .frame(width: 14, height: 14)
                .shadow(color: Color(hex: activePet.primaryColorHex), radius: 6)

            // Target Label Badge
            if let label = state.targetLabel {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(6)
                    .offset(y: 28)
            }
        }
        .position(target)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                beaconScale = 1.8
                beaconOpacity = 0.0
            }
        }
    }

    // MARK: - Companion Avatar
    private var companionAvatarView: some View {
        VStack(spacing: 2) {
            PetSpriteRenderer(pet: activePet, state: state.companionState, size: 56)
        }
    }

    // MARK: - Floating Speech & Alert Bubble
    private var shouldShowBubble: Bool {
        state.activeAlert != nil || !state.lastAIResponse.isEmpty || state.companionState == .listening || state.companionState == .thinking
    }

    private var floatingBubbleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let alert = state.activeAlert {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("\(alert.appName) Needs Input")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(alert.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3)

                Button(action: {
                    AccessibilityManager.shared.activateApplication(named: alert.appName)
                    state.clearAlert()
                }) {
                    Text("Focus \(alert.appName)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

            } else if state.companionState == .listening {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Listening...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            } else if state.companionState == .thinking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text(state.statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            } else if !state.lastAIResponse.isEmpty {
                Text(state.lastAIResponse)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12).opacity(0.88))
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .frame(maxWidth: 220)
    }

    // MARK: - Position Updating & Bézier Curve Glide
    private func updateCompanionPosition(screenHeight: CGFloat) {
        if let target = state.targetPoint {
            // Glide toward target element with spring physics
            let dx = target.x - petPosition.x
            let dy = target.y - petPosition.y
            petPosition.x += dx * 0.22
            petPosition.y += dy * 0.22
        } else {
            // Resting offset near physical mouse cursor (+35pt X, -20pt Y)
            let mouseCocoa = NSEvent.mouseLocation
            // Convert Cocoa screen coordinates to view coordinates
            let targetX = mouseCocoa.x + 35
            let targetY = screenHeight - mouseCocoa.y + 20

            let dx = targetX - petPosition.x
            let dy = targetY - petPosition.y

            // Organic smooth dampening
            petPosition.x += dx * 0.18
            petPosition.y += dy * 0.18
        }
    }
}

private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 122, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1.0)
    }
}
