import Foundation
import CoreGraphics
import SQLite3

/// Represents an individual executable step in a learned workflow
public struct WorkflowStep: Codable, Sendable {
    public let actionType: String  // "openApp", "click", "type", "return", "scroll"
    public let target: String?     // app name, text to type, or landmark name
    public let normX: Double?
    public let normY: Double?
    public let delayMs: Int?

    public init(actionType: String, target: String? = nil, normX: Double? = nil, normY: Double? = nil, delayMs: Int? = 600) {
        self.actionType = actionType
        self.target = target
        self.normX = normX
        self.normY = normY
        self.delayMs = delayMs
    }
}

/// Represents a learned workflow macro that can execute without slow vision analysis
public struct LearnedWorkflow: Sendable {
    public let intentKey: String
    public let appName: String
    public let steps: [WorkflowStep]
    public let executionCount: Int
    public let lastRun: Double
}

/// Persistent spatial landmark and workflow memory engine backed by SQLite
public final class AppMemoryStore: @unchecked Sendable {
    public static let shared = AppMemoryStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.sidekik.memory", qos: .utility)
    private var inMemoryLandmarks: [String: [String: CGPoint]] = [:]

    private init() {
        openDatabase()
        createTables()
        loadLandmarksIntoMemory()
        seedDefaultLandmarksIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func getDatabaseURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/sidekik", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("memory.sqlite3")
    }

    private func openDatabase() {
        let dbURL = getDatabaseURL()
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("Failed to open AppMemoryStore SQLite at \(dbURL.path)")
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS landmarks (
            app_name TEXT,
            landmark_key TEXT,
            norm_x REAL,
            norm_y REAL,
            confidence REAL,
            last_used REAL,
            PRIMARY KEY (app_name, landmark_key)
        );

        CREATE TABLE IF NOT EXISTS workflows (
            intent_key TEXT PRIMARY KEY,
            app_name TEXT,
            steps_json TEXT,
            execution_count INTEGER,
            last_run REAL
        );
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("Failed to initialize memory tables")
        }
    }

    private func loadLandmarksIntoMemory() {
        guard let db = self.db else { return }
        let query = "SELECT app_name, landmark_key, norm_x, norm_y FROM landmarks;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let app = String(cString: sqlite3_column_text(stmt, 0))
                let key = String(cString: sqlite3_column_text(stmt, 1))
                let x = sqlite3_column_double(stmt, 2)
                let y = sqlite3_column_double(stmt, 3)

                if inMemoryLandmarks[app] == nil {
                    inMemoryLandmarks[app] = [:]
                }
                inMemoryLandmarks[app]?[key] = CGPoint(x: x, y: y)
            }
        }
        sqlite3_finalize(stmt)
    }

    private func seedDefaultLandmarksIfNeeded() {
        if inMemoryLandmarks.isEmpty {
            // Seed common high-value landmarks
            rememberLandmark(app: "ChatGPT", key: "prompt_input", x: 500, y: 920)
            rememberLandmark(app: "ChatGPT", key: "new_chat_button", x: 120, y: 45)

            rememberLandmark(app: "Brave Browser", key: "omnibox", x: 500, y: 55)
            rememberLandmark(app: "Brave Browser", key: "new_tab", x: 280, y: 55)

            rememberLandmark(app: "Google Chrome", key: "omnibox", x: 500, y: 55)
            rememberLandmark(app: "Safari", key: "address_bar", x: 500, y: 55)

            rememberLandmark(app: "VN", key: "timeline", x: 500, y: 750)
            rememberLandmark(app: "VN", key: "speed_tool", x: 320, y: 840)
            rememberLandmark(app: "VN", key: "split_tool", x: 240, y: 840)
            rememberLandmark(app: "VN", key: "speed_0.5x", x: 420, y: 780)
            rememberLandmark(app: "VN", key: "confirm_check", x: 920, y: 840)
            rememberLandmark(app: "VN", key: "export_button", x: 930, y: 45)

            rememberLandmark(app: "System", key: "apple_logo", x: 15, y: 12)
            rememberLandmark(app: "System", key: "force_quit", x: 70, y: 160)

            // Seed common learned workflows
            let chatGPTSteps = [
                WorkflowStep(actionType: "openApp", target: "ChatGPT", delayMs: 700),
                WorkflowStep(actionType: "click", target: "prompt_input", normX: 500, normY: 920, delayMs: 400),
                WorkflowStep(actionType: "type", delayMs: 200),
                WorkflowStep(actionType: "return", delayMs: 100)
            ]
            recordWorkflow(intent: "open chatgpt and type", app: "ChatGPT", steps: chatGPTSteps)

            let forceQuitSteps = [
                WorkflowStep(actionType: "click", target: "apple_logo", normX: 15, normY: 12, delayMs: 650),
                WorkflowStep(actionType: "click", target: "force_quit", normX: 70, normY: 160, delayMs: 400)
            ]
            recordWorkflow(intent: "click on apple logo and then click on force quit", app: "System", steps: forceQuitSteps)

            let slowVideoSteps = [
                WorkflowStep(actionType: "click", target: "timeline", normX: 500, normY: 750, delayMs: 400),
                WorkflowStep(actionType: "click", target: "speed_tool", normX: 320, normY: 840, delayMs: 500),
                WorkflowStep(actionType: "click", target: "speed_0.5x", normX: 420, normY: 780, delayMs: 400),
                WorkflowStep(actionType: "click", target: "confirm_check", normX: 920, normY: 840, delayMs: 300)
            ]
            recordWorkflow(intent: "make the video 0.5x slower", app: "VN", steps: slowVideoSteps)
            recordWorkflow(intent: "make video slower", app: "VN", steps: slowVideoSteps)
        }
    }

    // MARK: - Landmarks Public API

    /// Saves or updates a known UI landmark coordinate
    public func rememberLandmark(app: String, key: String, x: Double, y: Double) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let cleanApp = app.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanApp.isEmpty, !cleanKey.isEmpty else { return }

            self.inMemoryLandmarks[cleanApp, default: [:]][cleanKey] = CGPoint(x: x, y: y)

            let sql = """
            INSERT INTO landmarks (app_name, landmark_key, norm_x, norm_y, confidence, last_used)
            VALUES (?, ?, ?, ?, 1.0, ?)
            ON CONFLICT(app_name, landmark_key) DO UPDATE SET
                norm_x = excluded.norm_x,
                norm_y = excluded.norm_y,
                confidence = MIN(2.0, confidence + 0.2),
                last_used = excluded.last_used;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (cleanApp as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (cleanKey as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 3, x)
                sqlite3_bind_double(stmt, 4, y)
                sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    /// Retrieves a cached landmark coordinate
    public func findLandmark(app: String, key: String) -> CGPoint? {
        if let point = inMemoryLandmarks[app]?[key] {
            return point
        }
        for (appName, dict) in inMemoryLandmarks {
            if appName.localizedCaseInsensitiveContains(app) || app.localizedCaseInsensitiveContains(appName) {
                if let pt = dict[key] {
                    return pt
                }
            }
        }
        return nil
    }

    /// Formats all remembered landmarks for an app into a concise prompt summary string
    public func getLandmarksSummary(app: String) -> String {
        var results: [String] = []
        for (appName, dict) in inMemoryLandmarks {
            if appName.localizedCaseInsensitiveContains(app) || app.localizedCaseInsensitiveContains(appName) || app == "Any" {
                for (key, pt) in dict {
                    results.append("\(key) at (\(Int(pt.x)), \(Int(pt.y)))")
                }
            }
        }
        if results.isEmpty {
            return "No previous landmarks recorded for \(app)."
        }
        return results.joined(separator: ", ")
    }

    // MARK: - Workflows Public API

    /// Persists a multi-step sequence into memory for instant repeat execution
    public func recordWorkflow(intent: String, app: String, steps: [WorkflowStep]) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            guard let jsonData = try? JSONEncoder().encode(steps),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

            let cleanKey = intent.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            let sql = """
            INSERT INTO workflows (intent_key, app_name, steps_json, execution_count, last_run)
            VALUES (?, ?, ?, 1, ?)
            ON CONFLICT(intent_key) DO UPDATE SET
                steps_json = excluded.steps_json,
                execution_count = execution_count + 1,
                last_run = excluded.last_run;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (cleanKey as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (app as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (jsonStr as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    /// Finds a matching learned workflow for an incoming prompt
    public func findWorkflow(forPrompt prompt: String) -> LearnedWorkflow? {
        guard let db = self.db else { return nil }
        let lower = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLower = lower.replacingOccurrences(of: "please ", with: "")
                              .replacingOccurrences(of: "can you ", with: "")
                              .replacingOccurrences(of: "could you ", with: "")
                              .replacingOccurrences(of: "hey ", with: "")
                              .trimmingCharacters(in: .whitespacesAndNewlines)

        let query = "SELECT intent_key, app_name, steps_json, execution_count, last_run FROM workflows;"
        var stmt: OpaquePointer?
        var matchedWorkflow: LearnedWorkflow? = nil

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(stmt, 0))
                let app = String(cString: sqlite3_column_text(stmt, 1))
                let jsonStr = String(cString: sqlite3_column_text(stmt, 2))
                let count = Int(sqlite3_column_int(stmt, 3))
                let lastRun = sqlite3_column_double(stmt, 4)

                // Match exact key, prefix, or contains match (e.g. "open chatgpt and type" matches "open chatgpt and type hello")
                if lower == key || lower.hasPrefix(key) || key.hasPrefix(lower) || lower.contains(key) ||
                   cleanLower == key || cleanLower.hasPrefix(key) || key.hasPrefix(cleanLower) || cleanLower.contains(key) {
                    if let data = jsonStr.data(using: .utf8),
                       let steps = try? JSONDecoder().decode([WorkflowStep].self, from: data) {
                        matchedWorkflow = LearnedWorkflow(
                            intentKey: key,
                            appName: app,
                            steps: steps,
                            executionCount: count,
                            lastRun: lastRun
                        )
                        break
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return matchedWorkflow
    }
}
