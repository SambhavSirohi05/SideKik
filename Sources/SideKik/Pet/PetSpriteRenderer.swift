import SwiftUI

/// Procedural 60fps sprite engine rendering pet characters and reactive animations
public struct PetSpriteRenderer: View {
    public let pet: PetIdentity
    public let state: CompanionState
    public let size: CGFloat

    @State private var blinkPhase: Bool = false
    @State private var breathePhase: Bool = false
    @State private var earTwitch: Bool = false
    @State private var orbitRotation: Double = 0.0
    @State private var alertBounce: CGFloat = 0.0
    @State private var speakingMouthScale: CGFloat = 1.0

    public init(pet: PetIdentity, state: CompanionState, size: CGFloat = 64) {
        self.pet = pet
        self.state = state
        self.size = size
    }

    private var primaryColor: Color {
        Color(hex: pet.primaryColorHex)
    }

    private var secondaryColor: Color {
        Color(hex: pet.secondaryColorHex)
    }

    private var accentColor: Color {
        Color(hex: pet.accentColorHex)
    }

    public var body: some View {
        ZStack {
            // Background ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [primaryColor.opacity(state == .alert ? 0.45 : 0.25), Color.clear],
                        center: .center,
                        startRadius: size * 0.2,
                        endRadius: size * 0.7
                    )
                )
                .scaleEffect(breathePhase ? 1.08 : 0.95)

            // Reactive particle rings (listening ripples or thinking orbit)
            if state == .listening {
                listeningRipples
            } else if state == .thinking {
                thinkingParticles
            } else if state == .alert {
                alertExclamation
            } else if state == .working {
                workingGears
            }

            // Character Body
            Group {
                switch pet.id {
                case "sparky":
                    sparkyAvatar
                case "ghosty":
                    ghostyAvatar
                case "pixelcat":
                    pixelCatAvatar
                default:
                    roboAvatar
                }
            }
            .offset(y: (state == .alert ? alertBounce : (breathePhase ? -2 : 2)))
        }
        .frame(width: size, height: size)
        .onAppear {
            startAnimations()
        }
        .onChange(of: state) { _, newState in
            handleStateChange(newState)
        }
    }

    // MARK: - Animations setup
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            breathePhase = true
        }
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            orbitRotation = 360.0
        }
    }

    private func handleStateChange(_ newState: CompanionState) {
        if newState == .alert {
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 5).repeatCount(4, autoreverses: true)) {
                alertBounce = -10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                alertBounce = 0
            }
        } else if newState == .speaking {
            withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                speakingMouthScale = 1.4
            }
        } else {
            speakingMouthScale = 1.0
        }
    }

    // MARK: - Pet: Sparky (Cyber Fox)
    private var sparkyAvatar: some View {
        ZStack {
            // Ears
            HStack(spacing: size * 0.35) {
                // Left Ear
                Triangle()
                    .fill(primaryColor)
                    .frame(width: size * 0.28, height: size * 0.32)
                    .rotationEffect(.degrees(-20 + (state == .listening ? -10 : 0)))
                // Right Ear
                Triangle()
                    .fill(primaryColor)
                    .frame(width: size * 0.28, height: size * 0.32)
                    .rotationEffect(.degrees(20 + (state == .listening ? 10 : 0)))
            }
            .offset(y: -size * 0.24)

            // Inner ears
            HStack(spacing: size * 0.42) {
                Triangle()
                    .fill(accentColor)
                    .frame(width: size * 0.14, height: size * 0.18)
                    .rotationEffect(.degrees(-20))
                Triangle()
                    .fill(accentColor)
                    .frame(width: size * 0.14, height: size * 0.18)
                    .rotationEffect(.degrees(20))
            }
            .offset(y: -size * 0.23)

            // Head
            Circle()
                .fill(
                    LinearGradient(
                        colors: [secondaryColor, primaryColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.65, height: size * 0.6)

            // White muzzle
            Ellipse()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.38, height: size * 0.26)
                .offset(y: size * 0.1)

            // Nose
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(y: size * 0.04)

            // Eyes
            HStack(spacing: size * 0.22) {
                eyeView
                eyeView
            }
            .offset(y: -size * 0.04)

            // Mouth
            if state == .speaking {
                Capsule()
                    .fill(Color.red.opacity(0.8))
                    .frame(width: size * 0.12 * speakingMouthScale, height: size * 0.08 * speakingMouthScale)
                    .offset(y: size * 0.14)
            }
        }
    }

    // MARK: - Pet: Ghosty (Ambient Spirit)
    private var ghostyAvatar: some View {
        ZStack {
            // Spirit Body
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(
                    LinearGradient(
                        colors: [accentColor, primaryColor.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.58, height: size * 0.62)
                .shadow(color: primaryColor.opacity(0.5), radius: 6)

            // Blushing Cheeks
            HStack(spacing: size * 0.32) {
                Circle().fill(Color.pink.opacity(0.6)).frame(width: size * 0.1, height: size * 0.08)
                Circle().fill(Color.pink.opacity(0.6)).frame(width: size * 0.1, height: size * 0.08)
            }
            .offset(y: size * 0.06)

            // Eyes
            HStack(spacing: size * 0.2) {
                Circle().fill(Color.black.opacity(0.8)).frame(width: size * 0.1, height: size * 0.1)
                Circle().fill(Color.black.opacity(0.8)).frame(width: size * 0.1, height: size * 0.1)
            }
            .offset(y: -size * 0.04)

            // Mouth
            if state == .speaking {
                Circle().fill(Color.black.opacity(0.7)).frame(width: size * 0.1 * speakingMouthScale, height: size * 0.1 * speakingMouthScale)
                    .offset(y: size * 0.1)
            }
        }
    }

    // MARK: - Pet: Pixel Cat
    private var pixelCatAvatar: some View {
        ZStack {
            // Blocky Cat Face
            RoundedRectangle(cornerRadius: 10)
                .fill(primaryColor)
                .frame(width: size * 0.62, height: size * 0.55)

            // Ears
            HStack(spacing: size * 0.34) {
                Rectangle().fill(primaryColor).frame(width: size * 0.18, height: size * 0.18).rotationEffect(.degrees(45))
                Rectangle().fill(primaryColor).frame(width: size * 0.18, height: size * 0.18).rotationEffect(.degrees(45))
            }
            .offset(y: -size * 0.24)

            // Eyes
            HStack(spacing: size * 0.22) {
                Rectangle().fill(Color.white).frame(width: size * 0.12, height: size * 0.12)
                    .overlay(Rectangle().fill(Color.black).frame(width: size * 0.06, height: size * 0.08))
                Rectangle().fill(Color.white).frame(width: size * 0.12, height: size * 0.12)
                    .overlay(Rectangle().fill(Color.black).frame(width: size * 0.06, height: size * 0.08))
            }
            .offset(y: -size * 0.03)

            // Whiskers
            HStack(spacing: size * 0.44) {
                VStack(spacing: 3) {
                    Rectangle().fill(Color.white.opacity(0.8)).frame(width: size * 0.1, height: 1.5)
                    Rectangle().fill(Color.white.opacity(0.8)).frame(width: size * 0.08, height: 1.5)
                }
                VStack(spacing: 3) {
                    Rectangle().fill(Color.white.opacity(0.8)).frame(width: size * 0.1, height: 1.5)
                    Rectangle().fill(Color.white.opacity(0.8)).frame(width: size * 0.08, height: 1.5)
                }
            }
            .offset(y: size * 0.06)
        }
    }

    // MARK: - Pet: Robo-Clicky
    private var roboAvatar: some View {
        ZStack {
            // Metallic Orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.9), Color(white: 0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.62, height: size * 0.62)
                .shadow(color: primaryColor.opacity(0.5), radius: 6)

            // Antenna
            VStack(spacing: 0) {
                Circle().fill(primaryColor).frame(width: size * 0.1, height: size * 0.1)
                Rectangle().fill(Color.gray).frame(width: 2, height: size * 0.12)
            }
            .offset(y: -size * 0.36)

            // Digital Visor
            Capsule()
                .fill(Color.black)
                .frame(width: size * 0.44, height: size * 0.22)
                .overlay(
                    HStack(spacing: size * 0.14) {
                        Circle().fill(primaryColor).frame(width: size * 0.09, height: size * 0.09)
                        Circle().fill(primaryColor).frame(width: size * 0.09, height: size * 0.09)
                    }
                )
                .offset(y: -size * 0.02)
        }
    }

    // MARK: - Eyes Component
    private var eyeView: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.9))
                .frame(width: size * 0.12, height: size * 0.12)
            // Catchlight sparkle
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.04, height: size * 0.04)
                .offset(x: -size * 0.02, y: -size * 0.02)
        }
    }

    // MARK: - Reactive Particle Overlays
    private var listeningRipples: some View {
        Circle()
            .stroke(accentColor.opacity(0.7), lineWidth: 2)
            .frame(width: size * 0.85, height: size * 0.85)
            .scaleEffect(breathePhase ? 1.25 : 0.9)
            .opacity(breathePhase ? 0.2 : 0.8)
    }

    private var thinkingParticles: some View {
        Circle()
            .trim(from: 0.1, to: 0.7)
            .stroke(
                AngularGradient(colors: [primaryColor, accentColor, Color.clear], center: .center),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 6])
            )
            .frame(width: size * 0.85, height: size * 0.85)
            .rotationEffect(.degrees(orbitRotation))
    }

    private var alertExclamation: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.yellow)
                .frame(width: 4, height: 12)
            Circle()
                .fill(Color.yellow)
                .frame(width: 4, height: 4)
        }
        .offset(y: -size * 0.45)
        .shadow(color: Color.orange, radius: 4)
    }

    private var workingGears: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: size * 0.25))
            .foregroundColor(accentColor)
            .rotationEffect(.degrees(orbitRotation * 2))
            .offset(x: size * 0.3, y: -size * 0.25)
    }
}

// Simple Triangle Shape helper for ears
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Color Hex initializer helper
private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 122, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1.0
        )
    }
}
