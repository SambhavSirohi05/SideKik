import Foundation
import SQLite3

/// Embedded SQLite database for storing interactions and SM-2 spaced repetition logs
public final class JournalDatabase: @unchecked Sendable {
    public static let shared = JournalDatabase()
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.sidekik.journaldb", qos: .utility)

    private init() {
        openDatabase()
        createTable()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func getDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SideKik", isDirectory: true)

        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("journal.db")
    }

    private func openDatabase() {
        let dbURL = getDatabaseURL()
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("Failed to open SQLite database at \(dbURL.path)")
        }
    }

    private func createTable() {
        let query = """
        CREATE TABLE IF NOT EXISTS journal (
            id TEXT PRIMARY KEY,
            timestamp REAL,
            app_name TEXT,
            question TEXT,
            answer TEXT,
            target_x REAL,
            target_y REAL,
            interval INTEGER,
            repetition INTEGER,
            ease_factor REAL
        );
        """
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Failed to create journal table")
            }
        }
        sqlite3_finalize(statement)
    }

    public func insertEntry(
        appName: String,
        question: String,
        answer: String,
        targetX: Double,
        targetY: Double
    ) {
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let id = UUID().uuidString
            let timestamp = Date().timeIntervalSince1970
            let interval = 1
            let repetition = 0
            let easeFactor = 2.5

            let query = """
            INSERT INTO journal (id, timestamp, app_name, question, answer, target_x, target_y, interval, repetition, ease_factor)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 2, timestamp)
                sqlite3_bind_text(statement, 3, (appName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 4, (question as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 5, (answer as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 6, targetX)
                sqlite3_bind_double(statement, 7, targetY)
                sqlite3_bind_int(statement, 8, Int32(interval))
                sqlite3_bind_int(statement, 9, Int32(repetition))
                sqlite3_bind_double(statement, 10, easeFactor)

                if sqlite3_step(statement) != SQLITE_DONE {
                    print("Failed to insert journal entry")
                }
            }
            sqlite3_finalize(statement)
        }
    }

    public func fetchRecent(limit: Int = 20) -> [JournalEntry] {
        var entries: [JournalEntry] = []
        guard let db = self.db else { return entries }

        let query = "SELECT id, timestamp, app_name, question, answer, target_x, target_y, interval, repetition, ease_factor FROM journal ORDER BY timestamp DESC LIMIT ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let timestamp = sqlite3_column_double(statement, 1)
                let appName = String(cString: sqlite3_column_text(statement, 2))
                let question = String(cString: sqlite3_column_text(statement, 3))
                let answer = String(cString: sqlite3_column_text(statement, 4))
                let targetX = sqlite3_column_double(statement, 5)
                let targetY = sqlite3_column_double(statement, 6)
                let interval = Int(sqlite3_column_int(statement, 7))
                let repetition = Int(sqlite3_column_int(statement, 8))
                let easeFactor = sqlite3_column_double(statement, 9)

                entries.append(JournalEntry(
                    id: id,
                    timestamp: timestamp,
                    appName: appName,
                    question: question,
                    answer: answer,
                    targetX: targetX,
                    targetY: targetY,
                    interval: interval,
                    repetition: repetition,
                    easeFactor: easeFactor
                ))
            }
        }
        sqlite3_finalize(statement)
        return entries
    }

    /// Calculates next review interval using SuperMemo-2 (SM-2) algorithm
    public func updateSM2(id: String, recallQuality: Int) {
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            // Fetch current item
            let querySelect = "SELECT interval, repetition, ease_factor FROM journal WHERE id = ?;"
            var statement: OpaquePointer?
            var interval = 1
            var repetition = 0
            var easeFactor = 2.5

            if sqlite3_prepare_v2(db, querySelect, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) == SQLITE_ROW {
                    interval = Int(sqlite3_column_int(statement, 0))
                    repetition = Int(sqlite3_column_int(statement, 1))
                    easeFactor = sqlite3_column_double(statement, 2)
                }
            }
            sqlite3_finalize(statement)

            // SM-2 calculation: q in 0..5
            let q = max(0, min(5, recallQuality))
            var newEaseFactor = easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
            if newEaseFactor < 1.3 { newEaseFactor = 1.3 }

            var newRepetition = repetition
            var newInterval = interval

            if q >= 3 {
                if repetition == 0 {
                    newInterval = 1
                } else if repetition == 1 {
                    newInterval = 6
                } else {
                    newInterval = Int(round(Double(interval) * newEaseFactor))
                }
                newRepetition += 1
            } else {
                newRepetition = 0
                newInterval = 1
            }

            let queryUpdate = "UPDATE journal SET interval = ?, repetition = ?, ease_factor = ? WHERE id = ?;"
            var updateStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, queryUpdate, -1, &updateStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(updateStmt, 1, Int32(newInterval))
                sqlite3_bind_int(updateStmt, 2, Int32(newRepetition))
                sqlite3_bind_double(updateStmt, 3, newEaseFactor)
                sqlite3_bind_text(updateStmt, 4, (id as NSString).utf8String, -1, nil)
                _ = sqlite3_step(updateStmt)
            }
            sqlite3_finalize(updateStmt)
        }
    }
}
