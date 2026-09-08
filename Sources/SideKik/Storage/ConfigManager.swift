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
    public var isPetEnabled: Bool

    public init(
        geminiApiKey: String = "",
        sarvamApiKey: String = "",
        selectedVoice: String = "shubh",
        selectedPetId: String = "azure",
        speechPace: Double = 1.05,
        autoClick: Bool = false,
        hasCompletedOnboarding: Bool = false,
        isPetEnabled: Bool = true
    ) {
        self.geminiApiKey = geminiApiKey
        self.sarvamApiKey = sarvamApiKey
        self.selectedVoice = selectedVoice
        self.selectedPetId = selectedPetId
        self.speechPace = speechPace
        self.autoClick = autoClick
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.isPetEnabled = isPetEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        geminiApiKey = try container.decodeIfPresent(String.self, forKey: .geminiApiKey) ?? ""
        sarvamApiKey = try container.decodeIfPresent(String.self, forKey: .sarvamApiKey) ?? ""
        selectedVoice = try container.decodeIfPresent(String.self, forKey: .selectedVoice) ?? "shubh"
        selectedPetId = try container.decodeIfPresent(String.self, forKey: .selectedPetId) ?? "azure"
        speechPace = try container.decodeIfPresent(Double.self, forKey: .speechPace) ?? 1.05
        autoClick = try container.decodeIfPresent(Bool.self, forKey: .autoClick) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        isPetEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPetEnabled) ?? true
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
                selectedPetId: "azure",
                speechPace: 1.05,
                autoClick: false,
                hasCompletedOnboarding: false,
                isPetEnabled: true
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
