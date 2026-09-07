import Foundation
import CoreGraphics

/// Structured reasoning result from a Vision-Language Model
public struct AIResponse: Sendable {
    public let spokenText: String
    public let rawText: String
    public let targetPointNormalized: CGPoint?
    public let targetLabel: String?

    public init(spokenText: String, rawText: String, targetPointNormalized: CGPoint? = nil, targetLabel: String? = nil) {
        self.spokenText = spokenText
        self.rawText = rawText
        self.targetPointNormalized = targetPointNormalized
        self.targetLabel = targetLabel
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
