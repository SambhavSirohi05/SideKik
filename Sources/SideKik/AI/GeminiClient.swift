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

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(cleanKey)") else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25.0

        let systemInstruction = """
        You are SideKik, an ambient, intelligent macOS desktop companion living beside the user's cursor.
        Current active application: \(activeAppName).
        The user is speaking to you. Answer their inquiry directly in 1 to 2 clear, spoken sentences (under 30 words).
        If the user asks where something is, how to click something, where an error is, or asks about any visual element on screen:
        Locate the exact control or area. Tag it at the end of your response using: [POINT:x,y:Label]
        where x and y are integers between 0 and 1000 representing normalized coordinates (0,0 is top-left, 1000,1000 is bottom-right), and Label is a 2-4 word description of the target.
        If no specific screen point is needed, do NOT include any [POINT:...] tag.
        Do NOT use markdown (no asterisks, bolding, or lists) as your response will be spoken aloud via text-to-speech.
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
                "maxOutputTokens": 300
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.networkError("Invalid HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(httpResponse.statusCode, errorText)
        }

        // Parse candidates
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let rawText = firstPart["text"] as? String else {
            throw GeminiError.decodingError("Empty response from Gemini")
        }

        return parseResponseText(rawText)
    }

    /// Extracts [POINT:x,y:Label] tags and returns clean spoken text and normalized coordinates
    public func parseResponseText(_ rawText: String) -> AIResponse {
        var point: CGPoint? = nil
        var label: String? = nil

        // Regex pattern: [POINT:x,y:label]
        let pattern = #"(?i)\[POINT:(\d+),(\d+)(?::([^\]]+))?\]"#
        var cleanSpoken = rawText

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = rawText as NSString
            let matches = regex.matches(in: rawText, range: NSRange(location: 0, length: nsString.length))

            if let match = matches.first {
                let xRange = match.range(at: 1)
                let yRange = match.range(at: 2)

                let xStr = nsString.substring(with: xRange)
                let yStr = nsString.substring(with: yRange)

                if let xVal = Double(xStr), let yVal = Double(yStr) {
                    point = CGPoint(x: xVal, y: yVal)
                }

                if match.numberOfRanges > 3 && match.range(at: 3).location != NSNotFound {
                    label = nsString.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                }

                // Strip the tag from spoken output
                cleanSpoken = regex.stringByReplacingMatches(
                    in: rawText,
                    range: NSRange(location: 0, length: nsString.length),
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return AIResponse(
            spokenText: cleanSpoken,
            rawText: rawText,
            targetPointNormalized: point,
            targetLabel: label
        )
    }
}
