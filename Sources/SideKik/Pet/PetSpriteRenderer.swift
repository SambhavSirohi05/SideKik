import SwiftUI

/// Sprite engine rendering authentic OpenPets characters with smooth frame-by-frame animations
public struct PetSpriteRenderer: View {
    public let pet: PetIdentity
    public let state: CompanionState
    public let size: CGFloat
    public let isMovingRight: Bool?

    @State private var breathePhase: Bool = false
    @State private var alertBounce: CGFloat = 0.0
    @State private var orbitRotation: Double = 0.0

    public init(
        pet: PetIdentity,
        state: CompanionState,
        size: CGFloat = 64,
        isMovingRight: Bool? = nil
    ) {
        self.pet = pet
        self.state = state
        self.size = size
        self.isMovingRight = isMovingRight
    }

    private var primaryColor: Color {
        Color(hex: pet.primaryColorHex)
    }

    private var accentColor: Color {
        Color(hex: pet.accentColorHex)
    }

    public var body: some View {
        ZStack {
            // Reactive particle rings (listening ripples or thinking orbit)
            if state == .listening {
                listeningRipples
            } else if state == .thinking {
                thinkingParticles
            } else if state == .alert {
                alertExclamation
            }

            // Authentic OpenPets Character Sprite
            AnimatedSpriteView(
                pet: pet,
                state: state,
                size: size,
                isMovingRight: isMovingRight
            )
            .offset(y: (state == .alert ? alertBounce : (breathePhase ? -1.5 : 1.5)))
        }
        .frame(width: size, height: size)
        .onAppear {
            startAmbientAnimations()
        }
        .onChange(of: state) { _, newState in
            handleStateChange(newState)
        }
    }

    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            breathePhase = true
        }
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            orbitRotation = 360.0
        }
    }

    private func handleStateChange(_ newState: CompanionState) {
        if newState == .alert {
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 5).repeatCount(4, autoreverses: true)) {
                alertBounce = -8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                alertBounce = 0
            }
        }
    }

    // MARK: - Reactive Particle Overlays
    private var listeningRipples: some View {
        Circle()
            .stroke(accentColor.opacity(0.7), lineWidth: 2)
            .frame(width: size * 0.9, height: size * 0.9)
            .scaleEffect(breathePhase ? 1.25 : 0.9)
            .opacity(breathePhase ? 0.2 : 0.8)
    }

    private var thinkingParticles: some View {
        Circle()
            .trim(from: 0.1, to: 0.7)
            .stroke(
                AngularGradient(colors: [primaryColor, accentColor, Color.clear], center: .center),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 6])
            )
            .frame(width: size * 0.9, height: size * 0.9)
            .rotationEffect(.degrees(orbitRotation))
    }

    private var alertExclamation: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.yellow)
                .frame(width: 3.5, height: 10)
            Circle()
                .fill(Color.yellow)
                .frame(width: 3.5, height: 3.5)
        }
        .offset(y: -size * 0.46)
        .shadow(color: Color.orange, radius: 4)
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
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
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
