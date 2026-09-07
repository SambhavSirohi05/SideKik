import Foundation
import SwiftUI
import AppKit

/// Unified states for the desktop companion pet and orchestrator
public enum CompanionState: String, Sendable, CaseIterable {
    case idle
    case listening
    case thinking
    case pointing
    case speaking
    case alert
    case working
    case happy
    case error
}

/// Agent alert notification payload
public struct AgentAlert: Identifiable, Sendable {
    public let id: UUID
    public let appName: String
    public let title: String
    public let message: String
    public let timestamp: Date
    public let windowFrame: NSRect?

    public init(id: UUID = UUID(), appName: String, title: String, message: String, timestamp: Date = Date(), windowFrame: NSRect? = nil) {
        self.id = id
        self.appName = appName
        self.title = title
        self.message = message
        self.timestamp = timestamp
        self.windowFrame = windowFrame
    }
}

/// Journal entry record
public struct JournalEntry: Identifiable, Sendable {
    public let id: String
    public let timestamp: Double
    public let appName: String
    public let question: String
    public let answer: String
    public let targetX: Double
    public let targetY: Double
    public let interval: Int
    public let repetition: Int
    public let easeFactor: Double
}

/// Main application observable state
@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // MARK: - Companion & Pet State
    @Published public var selectedPetId: String = "sparky"
    @Published public var companionState: CompanionState = .idle
    @Published public var statusMessage: String = "Ready"
    @Published public var lastSpokenTranscript: String = ""
    @Published public var lastAIResponse: String = ""
    @Published public var targetPoint: CGPoint? = nil
    @Published public var targetLabel: String? = nil
    @Published public var targetScreen: NSScreen? = nil
    @Published public var activeAppName: String = "Finder"

    // MARK: - Agent Alert & Working State
    @Published public var activeAlert: AgentAlert? = nil
    @Published public var activeTaskDescription: String? = nil
    @Published public var activeTaskProgress: Double? = nil

    // MARK: - Permissions
    @Published public var hasMicrophonePermission: Bool = false
    @Published public var hasScreenCapturePermission: Bool = false
    @Published public var hasAccessibilityPermission: Bool = false

    // MARK: - Settings & API Keys
    @Published public var geminiApiKey: String = ""
    @Published public var sarvamApiKey: String = ""
    @Published public var useLocalSpeechFallback: Bool = false
    @Published public var selectedVoice: String = "shubh"
    @Published public var speechPace: Double = 1.05

    // MARK: - History
    @Published public var recentEntries: [JournalEntry] = []

    private init() {}

    public func setAlert(_ alert: AgentAlert) {
        self.activeAlert = alert
        self.companionState = .alert
        self.statusMessage = "\(alert.appName) needs input"
    }

    public func clearAlert() {
        self.activeAlert = nil
        if self.companionState == .alert {
            self.companionState = .idle
            self.statusMessage = "Ready"
        }
    }
}
