import SwiftUI
import AppKit

/// Renders the companion pet avatar, independent companion cursor, Bézier glide flight, beacon highlight, and ambient speech bubble.
/// Hit-testing is passed through everywhere except the interactive tour HUD and voice interrupt buttons.
public struct CompanionCursorView: View {
    @ObservedObject private var state = AppState.shared

    @State private var petPosition: CGPoint = CGPoint(x: 300, y: 300)
    @State private var companionCursorPosition: CGPoint = CGPoint(x: 320, y: 320)
    @State private var isMovingRight: Bool? = nil
    @State private var isClicking: Bool = false
    @State private var bubbleOpacity: Double = 0.0
    @State private var timer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()

    private var activePet: PetIdentity {
        PetIdentity.find(byId: state.selectedPetId)
    }

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Pulsing Target Beacon Rings & Zone Spotlight
                if let target = state.targetPoint {
                    TargetBeaconView(
                        color: Color(hex: activePet.primaryColorHex),
                        label: state.targetLabel,
                        isTourMode: state.isTourActive
                    )
                    .position(target)
                }

                // 2. Independent Autonomous Companion Cursor (HeyClicky-style pointer)
                if state.targetPoint != nil || state.companionState == .pointing {
                    autonomousCompanionCursor
                        .position(companionCursorPosition)
                }

                // 3. Animated Companion Pet Avatar (OpenPets authentic sprite engine)
                if state.isPetEnabled {
                    companionAvatarView
                        .position(petPosition)
                        .transition(.scale.combined(with: .opacity))
                }

                // 4. Ambient Speech & Tour Control Callout
                if shouldShowBubble {
                    let bubbleX = min(geometry.size.width - 160, max(160, petPosition.x + 130))
                    let bubbleY = min(geometry.size.height - 90, max(90, petPosition.y - 60))

                    ambientBubbleView
                        .position(x: bubbleX, y: bubbleY)
                        .opacity(bubbleOpacity)
                        .onAppear {
                            updateBubbleHitRect(x: bubbleX, y: bubbleY, screenHeight: geometry.size.height)
                        }
                        .onChange(of: petPosition) { _, _ in
                            updateBubbleHitRect(x: bubbleX, y: bubbleY, screenHeight: geometry.size.height)
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
            .onReceive(timer) { _ in
                updateCompanionPosition(screenHeight: geometry.size.height)
            }
            .onChange(of: shouldShowBubble) { _, showing in
                withAnimation(.easeInOut(duration: 0.25)) {
                    bubbleOpacity = showing ? 1.0 : 0.0
                }
                if !showing {
                    state.bubbleRect = nil
                }
            }
            .onAppear {
                bubbleOpacity = shouldShowBubble ? 1.0 : 0.0
            }
        }
    }

    private func updateBubbleHitRect(x: CGFloat, y: CGFloat, screenHeight: CGFloat) {
        let cocoaY = screenHeight - y
        state.bubbleRect = NSRect(x: x - 150, y: cocoaY - 75, width: 300, height: 150)
    }

    // MARK: - Autonomous Companion Cursor Pointer (HeyClicky Style)
    private var autonomousCompanionCursor: some View {
        ZStack(alignment: .topLeading) {
            if isClicking {
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .scaleEffect(1.6)
                    .opacity(0.3)
                    .offset(x: -8, y: -8)
            }

            Image(systemName: "cursorarrow")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.black.opacity(0.45))
                .offset(x: 2, y: 3)

            Image(systemName: "cursorarrow")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color(hex: activePet.primaryColorHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                .scaleEffect(isClicking ? 0.85 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.5), value: isClicking)
        }
    }

    // MARK: - Companion Avatar
    private var companionAvatarView: some View {
        VStack(spacing: 2) {
            PetSpriteRenderer(
                pet: activePet,
                state: state.companionState,
                size: 58,
                isMovingRight: isMovingRight
            )
        }
    }

    // MARK: - Ambient Floating Speech Callout & Tour HUD
    private var shouldShowBubble: Bool {
        state.isTourActive || state.activeAlert != nil || !state.lastAIResponse.isEmpty || state.companionState == .listening || state.companionState == .thinking
    }

    private var ambientBubbleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header bar with Pet name & Tour Status & State Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: activePet.primaryColorHex))
                    .frame(width: 7, height: 7)
                Text(activePet.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))
                Spacer()

                if state.isTourActive {
                    Text("STEP \(state.currentTourStep)/\(state.totalTourSteps)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(Color(hex: activePet.primaryColorHex))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: activePet.primaryColorHex).opacity(0.20))
                        .cornerRadius(4)
                } else if state.companionState == .speaking {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("Speaking")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(4)
                }
            }

            // Body Content
            if let alert = state.activeAlert {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 11))
                    Text("\(alert.appName) Needs Input")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(alert.message)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.companionState == .listening {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("Listening...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
            } else if state.companionState == .thinking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5)
                    Text(state.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
            } else if !state.lastAIResponse.isEmpty {
                Text(state.lastAIResponse)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Subtle helper badge
            if state.isTourActive {
                HStack {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 8))
                    Text("Tour controls in Menu Bar")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.50))
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.08).opacity(0.94))
                .shadow(color: Color.black.opacity(0.40), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .frame(maxWidth: 300)
    }

    // MARK: - Position Updating & Cursor Trajectory
    private func updateCompanionPosition(screenHeight: CGFloat) {
        let mouseCocoa = NSEvent.mouseLocation
        let currentMouseX = mouseCocoa.x
        let currentMouseY = screenHeight - mouseCocoa.y

        if let target = state.targetPoint {
            // Companion cursor glides directly to the target point
            let cdx = target.x - companionCursorPosition.x
            let cdy = target.y - companionCursorPosition.y
            companionCursorPosition.x += cdx * 0.28
            companionCursorPosition.y += cdy * 0.28

            // Pet companion hovers slightly offset from target (-45pt X, -35pt Y)
            let petTargetX = target.x - 45
            let petTargetY = target.y - 35
            let pdx = petTargetX - petPosition.x
            let pdy = petTargetY - petPosition.y
            petPosition.x += pdx * 0.20
            petPosition.y += pdy * 0.20

            if abs(pdx) > 1.2 {
                isMovingRight = (pdx > 0)
            }
        } else {
            // Resting offset near physical mouse cursor (+35pt X, +20pt Y)
            let targetX = currentMouseX + 35
            let targetY = max(42, currentMouseY + 20)

            let dx = targetX - petPosition.x
            let dy = targetY - petPosition.y

            petPosition.x += dx * 0.18
            petPosition.y += dy * 0.18

            if abs(dx) > 1.2 {
                isMovingRight = (dx > 0)
            }

            companionCursorPosition = CGPoint(x: petPosition.x, y: max(38, petPosition.y))
        }
    }
}

/// Dedicated pulsing beacon component with double ripple rings, spotlight glow, and illuminated label
public struct TargetBeaconView: View {
    let color: Color
    let label: String?
    let isTourMode: Bool
    @State private var isPulsing: Bool = false

    public init(color: Color, label: String?, isTourMode: Bool = false) {
        self.color = color
        self.label = label
        self.isTourMode = isTourMode
    }

    public var body: some View {
        ZStack {
            // Outer expanding wave ring
            Circle()
                .stroke(color, lineWidth: isTourMode ? 3.0 : 2.5)
                .frame(width: isPulsing ? (isTourMode ? 90 : 64) : 20, height: isPulsing ? (isTourMode ? 90 : 64) : 20)
                .opacity(isPulsing ? 0.0 : 0.85)

            // Inner secondary wave ring
            Circle()
                .stroke(color.opacity(0.75), lineWidth: 1.5)
                .frame(width: isPulsing ? (isTourMode ? 60 : 44) : 16, height: isPulsing ? (isTourMode ? 60 : 44) : 16)
                .opacity(isPulsing ? 0.0 : 0.75)

            // Core glowing target bullseye
            Circle()
                .fill(color)
                .frame(width: isTourMode ? 16 : 14, height: isTourMode ? 16 : 14)
                .shadow(color: color, radius: isTourMode ? 12 : 8)

            // Target Label Badge Callout
            if let label = label {
                Text(label)
                    .font(.system(size: isTourMode ? 12 : 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, isTourMode ? 10 : 8)
                    .padding(.vertical, isTourMode ? 5 : 4)
                    .background(Color.black.opacity(0.88))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(color.opacity(0.8), lineWidth: 1)
                    )
                    .offset(y: isTourMode ? 36 : 30)
            }
        }
        .onAppear {
            withAnimation(Animation.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}
