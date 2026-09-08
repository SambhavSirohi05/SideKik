import Foundation
import CoreGraphics

/// Represents an individual recorded physical or agent action
public struct LoggedAction: Codable, Sendable {
    public let type: String            // "click", "type", "scroll", "openApp", "runShell", "return", "tourStep"
    public let target: String?         // UI element label or app name
    public let x: Double?
    public let y: Double?
    public let details: String?        // e.g. "dx: 0, dy: -8", "typed 'hello'"
    public let timestamp: Double

    public init(
        type: String,
        target: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        details: String? = nil,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.type = type
        self.target = target
        self.x = x
        self.y = y
        self.details = details
        self.timestamp = timestamp
    }
}

/// Comprehensive interaction log record capturing input, outputs, execution mode, and actions
public struct InteractionLogEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: String
    public let activeAppName: String
    public let input: String
    public let mode: String            // "fast_path_memory", "gemini_vision", "tour", "direct_action", "shell"
    public let output: String
    public let rawOutput: String?
    public let actions: [LoggedAction]
    public let landmarks: [String]
    public let durationMs: Double
    public let status: String          // "success", "error", "interrupted"
    public let diagnostics: String?

    public init(
        id: String = UUID().uuidString,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        activeAppName: String,
        input: String,
        mode: String,
        output: String,
        rawOutput: String? = nil,
        actions: [LoggedAction] = [],
        landmarks: [String] = [],
        durationMs: Double = 0.0,
        status: String = "success",
        diagnostics: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.activeAppName = activeAppName
        self.input = input
        self.mode = mode
        self.output = output
        self.rawOutput = rawOutput
        self.actions = actions
        self.landmarks = landmarks
        self.durationMs = durationMs
        self.status = status
        self.diagnostics = diagnostics
    }
}

/// Thread-safe logger maintaining a high-fidelity record of all agent interactions, inputs, outputs, and physical actions
public final class InteractionLogger: @unchecked Sendable {
    public static let shared = InteractionLogger()

    private let logQueue = DispatchQueue(label: "com.sidekik.interactionlogger", qos: .utility)
    private var inMemoryEntries: [InteractionLogEntry] = []
    private let maxInMemory = 100

    private let logsDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/sidekik", isDirectory: true)
    }()

    private var jsonlFileURL: URL {
        logsDirectory.appendingPathComponent("interactions.jsonl")
    }

    private var humanLogFileURL: URL {
        logsDirectory.appendingPathComponent("interactions.log")
    }

    private init() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        loadRecentEntries()
    }

    /// Records an interaction and flushes to disk
    public func record(_ entry: InteractionLogEntry) {
        logQueue.async { [weak self] in
            guard let self = self else { return }

            self.inMemoryEntries.append(entry)
            if self.inMemoryEntries.count > self.maxInMemory {
                self.inMemoryEntries.removeFirst(self.inMemoryEntries.count - self.maxInMemory)
            }

            // 1. Append JSONL
            if let data = try? JSONEncoder().encode(entry),
               let jsonStr = String(data: data, encoding: .utf8) {
                let line = jsonStr + "\n"
                if let fileHandle = try? FileHandle(forWritingTo: self.jsonlFileURL) {
                    fileHandle.seekToEndOfFile()
                    if let lineData = line.data(using: .utf8) {
                        fileHandle.write(lineData)
                    }
                    try? fileHandle.close()
                } else {
                    try? line.write(to: self.jsonlFileURL, atomically: true, encoding: .utf8)
                }
            }

            // 2. Append Human-Readable Formatted Log
            var actionLines = ""
            if !entry.actions.isEmpty {
                actionLines = "  ACTIONS PERFORMED:\n" + entry.actions.map { action in
                    var loc = ""
                    if let x = action.x, let y = action.y {
                        loc = " at (\(Int(x)), \(Int(y)))"
                    }
                    let det = action.details.map { " [\($0)]" } ?? ""
                    return "    • \(action.type.uppercased()): \(action.target ?? "target")\(loc)\(det)"
                }.joined(separator: "\n")
            } else {
                actionLines = "  ACTIONS PERFORMED: None (voice response only)"
            }

            var landmarksLine = ""
            if !entry.landmarks.isEmpty {
                landmarksLine = "\n  LANDMARKS: " + entry.landmarks.joined(separator: ", ")
            }

            var diagLine = ""
            if let diag = entry.diagnostics, !diag.isEmpty {
                diagLine = "\n  DIAGNOSTICS / LACKING: \(diag)"
            }

            let humanEntry = """
            ================================================================================
            [\(entry.timestamp)] APP: \(entry.activeAppName) | MODE: \(entry.mode) | LATENCY: \(Int(entry.durationMs))ms | STATUS: \(entry.status)
            --------------------------------------------------------------------------------
              INPUT:  "\(entry.input)"
              OUTPUT: "\(entry.output)"
            \(actionLines)\(landmarksLine)\(diagLine)
            ================================================================================

            """

            if let fileHandle = try? FileHandle(forWritingTo: self.humanLogFileURL) {
                fileHandle.seekToEndOfFile()
                if let textData = humanEntry.data(using: .utf8) {
                    fileHandle.write(textData)
                }
                try? fileHandle.close()
            } else {
                try? humanEntry.write(to: self.humanLogFileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Returns recent interaction entries
    public func recentEntries(limit: Int = 20) -> [InteractionLogEntry] {
        var results: [InteractionLogEntry] = []
        logQueue.sync {
            results = Array(self.inMemoryEntries.suffix(limit).reversed())
        }
        return results
    }

    /// Returns the human-readable log content
    public func formattedLog(limitLines: Int = 100) -> String {
        guard let content = try? String(contentsOf: humanLogFileURL, encoding: .utf8) else {
            return "No interactions logged yet."
        }
        let lines = content.components(separatedBy: "\n")
        if lines.count > limitLines {
            return lines.suffix(limitLines).joined(separator: "\n")
        }
        return content
    }

    private func loadRecentEntries() {
        guard FileManager.default.fileExists(atPath: jsonlFileURL.path),
              let content = try? String(contentsOf: jsonlFileURL, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var loaded: [InteractionLogEntry] = []
        for line in lines.suffix(maxInMemory) {
            if let data = line.data(using: .utf8),
               let entry = try? JSONDecoder().decode(InteractionLogEntry.self, from: data) {
                loaded.append(entry)
            }
        }
        self.inMemoryEntries = loaded
    }
}
