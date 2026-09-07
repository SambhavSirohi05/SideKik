import Foundation
import CoreGraphics

public enum AIActionType: Sendable, Equatable {
    case point
    case click
    case openApp(String)
    case runShell(String)
    case typeText(String)
    case done(String)
}

/// Individual milestone in a multi-step guided tour
public struct TourStep: Sendable, Equatable {
    public let pointNormalized: CGPoint
    public let label: String
    public let narration: String

    public init(pointNormalized: CGPoint, label: String, narration: String) {
        self.pointNormalized = pointNormalized
        self.label = label
        self.narration = narration
    }
}

/// Structured reasoning result from a Vision-Language Model
public struct AIResponse: Sendable {
    public let spokenText: String
    public let rawText: String
    public let targetPointNormalized: CGPoint?
    public let targetLabel: String?
    public let action: AIActionType?
    public let tourSteps: [TourStep]?

    public init(
        spokenText: String,
        rawText: String,
        targetPointNormalized: CGPoint? = nil,
        targetLabel: String? = nil,
        action: AIActionType? = nil,
        tourSteps: [TourStep]? = nil
    ) {
        self.spokenText = spokenText
        self.rawText = rawText
        self.targetPointNormalized = targetPointNormalized
        self.targetLabel = targetLabel
        self.action = action
        self.tourSteps = tourSteps
    }
}

/// Unified protocol for multimodal vision reasoning clients
public protocol AIClient: Sendable {
    func analyzeScreen(
        question: String,
        imageBase64: String,
        activeAppName: String,
        apiKey: String
    ) async throws -> AIResponse
}
