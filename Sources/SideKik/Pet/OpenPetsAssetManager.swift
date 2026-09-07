import Foundation
import AppKit
import CoreGraphics

/// OpenPets standardized animation state matching the 9 rows of the 1536x1872 spritesheet
public enum OpenPetAnimationState: String, Sendable, CaseIterable {
    case idle = "idle"                     // Row 0: 6 frames
    case runningRight = "running-right"   // Row 1: 8 frames
    case runningLeft = "running-left"     // Row 2: 8 frames
    case waving = "waving"                 // Row 3: 4 frames (Alert / Greeting)
    case jumping = "jumping"               // Row 4: 5 frames (Happy / Celebration)
    case failed = "failed"                 // Row 5: 8 frames (Error / Confused)
    case waiting = "waiting"               // Row 6: 6 frames (Listening / Waiting)
    case running = "running"               // Row 7: 6 frames (Working / Active)
    case review = "review"                 // Row 8: 6 frames (Pointing / Reading / Inspect)

    public var row: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .running: return 7
        case .review: return 8
        }
    }

    public var frameCount: Int {
        switch self {
        case .idle: return 6
        case .runningRight: return 8
        case .runningLeft: return 8
        case .waving: return 4
        case .jumping: return 5
        case .failed: return 8
        case .waiting: return 6
        case .running: return 6
        case .review: return 6
        }
    }

    public var frameDuration: TimeInterval {
        switch self {
        case .idle: return 0.20        // 1.2s cycle
        case .runningRight, .runningLeft: return 0.09 // 0.72s cycle
        case .waving: return 0.14      // 0.56s cycle
        case .jumping: return 0.12     // 0.60s cycle
        case .failed: return 0.12      // 0.96s cycle
        case .waiting: return 0.16     // 0.96s cycle
        case .running: return 0.11     // 0.66s cycle
        case .review: return 0.16      // 0.96s cycle
        }
    }
}

/// Manages loading, slicing, and memory-caching of OpenPets character sprite sheets
public final class OpenPetsAssetManager: @unchecked Sendable {
    public static let shared = OpenPetsAssetManager()

    public static let frameWidth: CGFloat = 192.0
    public static let frameHeight: CGFloat = 208.0
    public static let columns: Int = 8
    public static let rows: Int = 9

    // In-memory cache of sliced CGImages: [PetId: [OpenPetAnimationState: [CGImage]]]
    private var frameCache: [String: [OpenPetAnimationState: [CGImage]]] = [:]
    private let lock = NSLock()

    private let localPetsDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/sidekik/pets", isDirectory: true)
    }()

    private init() {
        try? FileManager.default.createDirectory(at: localPetsDirectory, withIntermediateDirectories: true)
    }

    public func resolvedPetName(forPetId petId: String) -> String {
        switch petId.lowercased() {
        case "sparky", "fenne-fox", "fenne": return "fenne-fox"
        case "pixelcat", "yuzu-golden-kitten", "yuzu": return "yuzu-golden-kitten"
        case "ghosty", "default-pet", "barnaby": return "default-pet"
        case "robo", "banana-skater", "banana": return "banana-skater"
        default: return petId
        }
    }

    /// Retrieves frames for a given pet persona and animation state
    public func frames(forPetId petId: String, state: OpenPetAnimationState) -> [CGImage]? {
        let resolvedId = resolvedPetName(forPetId: petId)
        lock.lock()
        if let petFrames = frameCache[resolvedId], let stateFrames = petFrames[state], !stateFrames.isEmpty {
            lock.unlock()
            return stateFrames
        }
        lock.unlock()

        // Attempt to load and slice from local disk
        loadPetSpritesheet(forPetId: resolvedId)

        lock.lock()
        defer { lock.unlock() }
        return frameCache[resolvedId]?[state]
    }

    /// Loads and slices the 8x9 spritesheet into individual CGImage frames
    @discardableResult
    public func loadPetSpritesheet(forPetId petId: String) -> Bool {
        let resolvedId = resolvedPetName(forPetId: petId)
        let localFile = localPetsDirectory.appendingPathComponent("\(resolvedId).webp")

        guard FileManager.default.fileExists(atPath: localFile.path) else {
            // Spritesheet missing: trigger background download
            downloadSpritesheetIfNeeded(forPetId: resolvedId)
            return false
        }

        guard let nsImage = NSImage(contentsOf: localFile),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Failed to decode WebP spritesheet at: \(localFile.path)")
            return false
        }

        var slicedStateFrames: [OpenPetAnimationState: [CGImage]] = [:]

        for state in OpenPetAnimationState.allCases {
            var stateFrames: [CGImage] = []
            let row = state.row
            let frameCount = state.frameCount

            for col in 0..<frameCount {
                let cropRect = CGRect(
                    x: CGFloat(col) * Self.frameWidth,
                    y: CGFloat(row) * Self.frameHeight,
                    width: Self.frameWidth,
                    height: Self.frameHeight
                )
                if let cropped = cgImage.cropping(to: cropRect) {
                    stateFrames.append(cropped)
                }
            }
            slicedStateFrames[state] = stateFrames
        }

        lock.lock()
        frameCache[resolvedId] = slicedStateFrames
        lock.unlock()

        return true
    }

    /// Downloads spritesheet from OpenPets CDN if not present locally
    private func downloadSpritesheetIfNeeded(forPetId petId: String) {
        let resolvedId = resolvedPetName(forPetId: petId)
        let destination = localPetsDirectory.appendingPathComponent("\(resolvedId).webp")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        guard let remoteURL = remoteURL(forPetId: resolvedId) else { return }

        Task.detached(priority: .utility) { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: remoteURL)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    try data.write(to: destination)
                    self?.loadPetSpritesheet(forPetId: resolvedId)
                    print("Successfully downloaded OpenPets spritesheet for: \(resolvedId)")
                }
            } catch {
                print("Failed to fetch OpenPets spritesheet for \(resolvedId): \(error.localizedDescription)")
            }
        }
    }

    private func remoteURL(forPetId petId: String) -> URL? {
        let resolved = resolvedPetName(forPetId: petId)
        switch resolved {
        case "fenne-fox":
            return URL(string: "https://openpets.dev/pets/fenne-fox-openpets/spritesheet.webp")
        case "yuzu-golden-kitten":
            return URL(string: "https://openpets.dev/pets/yuzu-golden-kitten-openpets/spritesheet.webp")
        case "default-pet":
            return URL(string: "https://raw.githubusercontent.com/OpenPetsHQ/openpets/main/apps/desktop/assets/default-pet-spritesheet.webp")
        case "banana-skater":
            return URL(string: "https://openpets.dev/pets/banana-skater-openpets/spritesheet.webp")
        default:
            return URL(string: "https://openpets.dev/pets/fenne-fox-openpets/spritesheet.webp")
        }
    }
}
