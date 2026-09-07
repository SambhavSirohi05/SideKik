import Foundation

/// Fast, secure local JSON configuration stored in ~/.config/sidekik/config.json with 0600 permissions.
/// Avoids annoying macOS Keychain authorization password dialogs on launch.
public struct SideKikConfig: Codable, Sendable {
    public var geminiApiKey: String
    public var sarvamApiKey: String
    public var selectedVoice: String
    public var selectedPetId: String
    public var speechPace: Double
    public var autoClick: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        geminiApiKey: String = "",
        sarvamApiKey: String = "",
        selectedVoice: String = "shubh",
        selectedPetId: String = "sparky",
        speechPace: Double = 1.05,
        autoClick: Bool = false,
        hasCompletedOnboarding: Bool = false
    ) {
        self.geminiApiKey = geminiApiKey
        self.sarvamApiKey = sarvamApiKey
        self.selectedVoice = selectedVoice
        self.selectedPetId = selectedPetId
        self.speechPace = speechPace
        self.autoClick = autoClick
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

public final class ConfigManager: @unchecked Sendable {
    public static let shared = ConfigManager()
    private let fileManager = FileManager.default
    private let lock = NSLock()

    private init() {
        ensureDirectory()
    }

    private var configFileURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/sidekik/config.json")
    }

    private func ensureDirectory() {
        let dir = configFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func load() -> SideKikConfig {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: configFileURL),
              let config = try? JSONDecoder().decode(SideKikConfig.self, from: data) else {
            // Default config
            return SideKikConfig(
                geminiApiKey: "",
                sarvamApiKey: "",
                selectedVoice: "shubh",
                selectedPetId: "sparky",
                speechPace: 1.05,
                autoClick: false,
                hasCompletedOnboarding: false
            )
        }
        return config
    }

    public func save(_ config: SideKikConfig) {
        lock.lock()
        defer { lock.unlock() }

        ensureDirectory()
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configFileURL, options: .atomic)
            // Set 0600 permissions
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFileURL.path)
        }
    }
}
