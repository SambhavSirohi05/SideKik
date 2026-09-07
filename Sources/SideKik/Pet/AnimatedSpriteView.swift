import SwiftUI
import AppKit

/// 60fps frame-stepper view rendering smooth OpenPets character animation cycles
public struct AnimatedSpriteView: View {
    public let pet: PetIdentity
    public let state: CompanionState
    public let size: CGFloat
    public let isMovingRight: Bool?

    @State private var currentFrameIndex: Int = 0
    @State private var currentAnimationState: OpenPetAnimationState = .idle
    @State private var timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

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

    private var targetAnimationState: OpenPetAnimationState {
        switch state {
        case .pointing, .working:
            if let movingRight = isMovingRight {
                return movingRight ? .runningRight : .runningLeft
            }
            return .running
        case .speaking:
            return .review
        case .listening:
            return .waiting
        case .thinking:
            return .review
        case .alert:
            return .waving
        case .happy:
            return .jumping
        case .error:
            return .failed
        case .idle:
            return .idle
        }
    }

    private var activeFrames: [CGImage] {
        OpenPetsAssetManager.shared.frames(forPetId: pet.id, state: currentAnimationState) ?? []
    }

    public var body: some View {
        ZStack {
            if !activeFrames.isEmpty {
                let validIndex = min(currentFrameIndex, max(0, activeFrames.count - 1))
                let cgFrame = activeFrames[validIndex]

                Image(decorative: cgFrame, scale: 2.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size * (OpenPetsAssetManager.frameHeight / OpenPetsAssetManager.frameWidth))
                    .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 2)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            updateAnimationState(targetAnimationState)
        }
        .onChange(of: state) { _, _ in
            updateAnimationState(targetAnimationState)
        }
        .onChange(of: isMovingRight) { _, _ in
            updateAnimationState(targetAnimationState)
        }
        .onReceive(timer) { _ in
            let count = activeFrames.count
            if count > 0 {
                currentFrameIndex = (currentFrameIndex + 1) % count
            }
        }
    }

    private func updateAnimationState(_ nextState: OpenPetAnimationState) {
        guard nextState != currentAnimationState else { return }
        currentAnimationState = nextState
        currentFrameIndex = 0
        timer = Timer.publish(every: nextState.frameDuration, on: .main, in: .common).autoconnect()
    }
}
