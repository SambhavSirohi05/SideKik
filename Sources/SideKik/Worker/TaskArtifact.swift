import Foundation

public enum TaskStatus: String, Sendable, Codable {
    case pending
    case running
    case completed
    case failed
    case needsApproval
}

/// Represents an asynchronous background goal or job
public struct BackgroundTask: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let brief: String
    public var status: TaskStatus
    public var progress: Double
    public let createdAt: Date
    public var completedAt: Date?
    public var artifactPath: String?
    public var resultSummary: String?

    public init(
        id: UUID = UUID(),
        title: String,
        brief: String,
        status: TaskStatus = .pending,
        progress: Double = 0.0,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        artifactPath: String? = nil,
        resultSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.brief = brief
        self.status = status
        self.progress = progress
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.artifactPath = artifactPath
        self.resultSummary = resultSummary
    }
}
