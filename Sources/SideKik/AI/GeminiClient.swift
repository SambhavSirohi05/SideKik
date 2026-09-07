import Foundation
import CoreGraphics

public enum GeminiError: Error, LocalizedError, Sendable {
    case missingApiKey
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Google Gemini API key is missing. Add your free key in Settings."
        case .invalidURL:
            return "Invalid Gemini endpoint URL."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "Gemini API error (\(code)): \(msg)"
        case .decodingError(let msg):
            return "Failed to parse Gemini response: \(msg)"
        }
    }
}

/// Zero-cost multimodal client using Google Gemini 2.0 Flash REST API
public final class GeminiClient: AIClient {
    public static let shared = GeminiClient()
    private let session = URLSession.shared

    private init() {}

    public func analyzeScreen(
        question: String,
        imageBase64: String,
        activeAppName: String,
        apiKey: String
    ) async throws -> AIResponse {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw GeminiError.missingApiKey
        }

        let modelCandidates = ["gemini-3.5-flash", "gemini-flash-latest", "gemini-2.5-flash"]
        var lastError: Error = GeminiError.apiError(404, "No model available")

        for model in modelCandidates {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(cleanKey)") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 25.0

            let memorySummary = AppMemoryStore.shared.getLandmarksSummary(app: activeAppName)

            let systemInstruction = """
            You are SideKik, an ambient, intelligent macOS desktop companion living beside the user's cursor.
            Current active application: \(activeAppName).

            Spatial Memory of Known UI Landmarks for \(activeAppName):
            \(memorySummary)
            (If the user's inquiry relates to a known landmark above, verify its presence and prioritize those coordinates).

            You have the ability to guide the user visually AND perform actions on-screen and off-screen:
            1. If the user asks where something is, asks for guidance, or asks to locate something on screen:
               Locate the exact control or area. Tag it at the end with: [POINT:x,y:Label]
            2. If the user asks to click, select, or tap an element on screen (e.g., "click save", "click settings", "click it", "open tab", "select clip"):
               Tag it at the end with: [CLICK:x,y:Label]
            3. If the user asks to open or launch an application (e.g., "open Safari", "launch Terminal", "open Slack"):
               Tag it at the end with: [OPEN:AppName]
            4. If the user asks to run a terminal/shell command:
               Tag it at the end with: [RUN:command]
            5. If the user asks to teach them how to use the app, asks for a tour, asks for a walkthrough, or asks to explain the interface (e.g., "teach me how to use this", "walk me through this UI", "show me what things do", "give me a tour", "explain this app", "teach me how to edit in VN"):
               Identify 4 to 6 distinct, well-separated key functional zones across the application window in a logical walkthrough order (e.g., 1. Top Header/Navigation, 2. Primary Left Sidebar/Explorer/Media Pool, 3. Main Workspace/Editor/Canvas, 4. Timeline/Track/Speed Panel, 5. Bottom Status/Terminal).
               Output each milestone in order using:
               [STEP:x,y:Zone Name:2 spoken sentences explaining this area and what you can do here]
               CRITICAL TOUR RULES:
               - NEVER reply with conversational pleasantries like "I would be happy to..." or "Sure, let's explore...".
               - Start directly with: "Here is a guided walkthrough of \(activeAppName):"
               - You MUST output at least 4 [STEP:...] tags in your response right now. Do not delay or ask questions.
            6. If performing a multi-step task and the goal has been fully completed:
               Tag it at the end with: [DONE:Summary of completed goal]
            7. If the user asks to scroll a document/page, scrub a video editing timeline, or reveal off-screen items:
               Tag it at the end with: [SCROLL:dx,dy:Label]
               - dy: negative to scroll down / reveal below (e.g. -6), positive to scroll up (e.g. +6).
               - dx: negative to scroll/scrub right along a timeline (e.g. -6), positive to scrub left (e.g. +6).

            Coordinate Precision Rules:
            - Coordinates (x, y) are integers from 0 to 1000 representing normalized coordinates (0,0 is top-left, 1000,1000 is bottom-right).
            - For [CLICK:x,y:Label] and [POINT:x,y:Label], pinpoint the EXACT CENTER of the target element (the button, tab label, or link text).
            - Avoid adjacent icons, avatars, or card margins. Land squarely inside the clickable text or button body.
            - macOS Menu Bar Note: The macOS menu bar is at the very top (y < 35). NEVER click at y < 35 unless the user explicitly requested a menu bar item (e.g. Apple menu, File, Edit, etc.).
            - Browser Tabs Note: In web browsers (Brave, Chrome, Safari), tabs are situated below the menu bar, typically between y = 45 and y = 85. Ensure coordinates for browser tabs land in the middle of the tab title bar (y > 45).
            - Label is a concise 2-4 word description of the target.

            Spoken Response Length:
            - For general questions and actions, answer directly in 1 to 2 clear spoken sentences (under 35 words).
            - For tours and walkthroughs (rule 5), output a 1-sentence friendly intro followed immediately by the 4 to 6 [STEP:...] tags.
            - Do NOT use markdown (no asterisks, bolding, or lists) as your response will be spoken aloud via text-to-speech.
            """

        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(systemInstruction)\n\nUser Question: \(question)"],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": imageBase64
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 1024
            ]
        ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = GeminiError.networkError("Invalid HTTP response")
                    continue
                }

                if httpResponse.statusCode != 200 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    lastError = GeminiError.apiError(httpResponse.statusCode, errorText)
                    continue
                }

                // Parse candidates
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let rawText = firstPart["text"] as? String else {
                    lastError = GeminiError.decodingError("Empty response from Gemini")
                    continue
                }

                return parseResponseText(rawText)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError
    }

    /// Extracts action and point tags and returns clean spoken text and action metadata
    public func parseResponseText(_ rawText: String) -> AIResponse {
        var point: CGPoint? = nil
        var label: String? = nil
        var action: AIActionType? = nil

        let nsString = rawText as NSString

        // 1. Check for [CLICK:x,y:label] with flexible whitespace
        let clickPattern = #"(?i)\[CLICK:\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)(?:\s*:\s*([^\]]+))?\]"#
        if let regex = try? NSRegularExpression(pattern: clickPattern),
           let match = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)).first {
            let xStr = nsString.substring(with: match.range(at: 1))
            let yStr = nsString.substring(with: match.range(at: 2))
            if let xVal = Double(xStr), let yVal = Double(yStr) {
                point = CGPoint(x: xVal, y: yVal)
                action = .click
            }
            if match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound {
                label = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            }
        }

        // 2. Check for [POINT:x,y:label] with flexible whitespace
        let pointPattern = #"(?i)\[POINT:\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)(?:\s*:\s*([^\]]+))?\]"#
        if let regex = try? NSRegularExpression(pattern: pointPattern),
           let match = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)).first {
            let xStr = nsString.substring(with: match.range(at: 1))
            let yStr = nsString.substring(with: match.range(at: 2))
            if let xVal = Double(xStr), let yVal = Double(yStr) {
                point = CGPoint(x: xVal, y: yVal)
                if action == nil { action = .point }
            }
            if match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound {
                label = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            }
        }

        // 3. Check for [OPEN:AppName]
        let openPattern = #"(?i)\[OPEN:\s*([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: openPattern),
           let match = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)).first {
            let appName = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            action = .openApp(appName)
        }

        // 4. Check for [RUN:command]
        let runPattern = #"(?i)\[RUN:\s*([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: runPattern),
           let match = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)).first {
            let cmd = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            action = .runShell(cmd)
        }

        // 5. Check for [TYPE:text]
        let typePattern = #"(?i)\[TYPE:\s*([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: typePattern),
           let match = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)).first {
            let txt = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            action = .typeText(txt)
        }

        // 6. Check for [DONE:summary]
        let donePattern = #"(?i)\[DONE:\s*([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: donePattern),
           let match = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)).first {
            let summary = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            action = .done(summary)
        }

        // 7. Check for [SCROLL:dx,dy:label]
        let scrollPattern = #"(?i)\[SCROLL:\s*(-?\d+)\s*,\s*(-?\d+)(?:\s*:\s*([^\]]+))?\]"#
        if let regex = try? NSRegularExpression(pattern: scrollPattern),
           let match = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length)).first {
            let dxStr = nsString.substring(with: match.range(at: 1))
            let dyStr = nsString.substring(with: match.range(at: 2))
            if let dxVal = Int32(dxStr), let dyVal = Int32(dyStr) {
                var scrollLabel: String? = nil
                if match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound {
                    scrollLabel = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                }
                action = .scroll(dxVal, dyVal, scrollLabel)
            }
        }

        // 8. Check for Multi-Step Tour [STEP:x,y:Label:Narration] or [STEP 1:x,y:Label:Narration]
        let stepPattern = #"(?is)\[STEP(?:\s*\d+)?:\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*:\s*([^:\r\n\]]+)\s*:\s*([^\]]+)\]"#
        var tourSteps: [TourStep] = []
        if let regex = try? NSRegularExpression(pattern: stepPattern) {
            let matches = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let xStr = nsString.substring(with: match.range(at: 1))
                let yStr = nsString.substring(with: match.range(at: 2))
                let stepLabel = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
                let narration = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let xVal = Double(xStr), let yVal = Double(yStr) {
                    tourSteps.append(TourStep(
                        pointNormalized: CGPoint(x: xVal, y: yVal),
                        label: stepLabel,
                        narration: narration
                    ))
                }
            }
        }

        // Clean all brackets tags from spoken text
        let cleanTagPattern = #"(?is)\[(CLICK|POINT|OPEN|RUN|TYPE|STEP|DONE|SCROLL):[^\]]+\]"#
        var cleanSpoken = rawText
        if let stripRegex = try? NSRegularExpression(pattern: cleanTagPattern) {
            cleanSpoken = stripRegex.stringByReplacingMatches(
                in: cleanSpoken,
                range: NSRange(location: 0, length: (cleanSpoken as NSString).length),
                withTemplate: ""
            )
        }

        cleanSpoken = cleanSpoken.trimmingCharacters(in: .whitespacesAndNewlines)

        return AIResponse(
            spokenText: cleanSpoken,
            rawText: rawText,
            targetPointNormalized: point,
            targetLabel: label,
            action: action,
            tourSteps: tourSteps.isEmpty ? nil : tourSteps
        )
    }
}
