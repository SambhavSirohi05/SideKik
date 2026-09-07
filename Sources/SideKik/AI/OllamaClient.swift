import Foundation
import CoreGraphics

/// Optional local Ollama client fallback (qwen2.5vl:7b)
public final class OllamaClient: AIClient {
    public static let shared = OllamaClient()
    private let session = URLSession.shared
    private let endpointURL = URL(string: "http://127.0.0.1:11434/api/chat")!

    private init() {}

    public func analyzeScreen(
        question: String,
        imageBase64: String,
        activeAppName: String,
        apiKey: String
    ) async throws -> AIResponse {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45.0

        let systemInstruction = """
        You are SideKik, a helpful macOS desktop companion.
        Active application: \(activeAppName).
        Answer the user's question in 1 to 2 spoken sentences (under 30 words).
        If indicating where to click, tag with [POINT:x,y:Label] where x,y are 0-1000 normalized coordinates.
        Do not use markdown.
        """

        let payload: [String: Any] = [
            "model": "qwen2.5vl:7b",
            "stream": false,
            "messages": [
                [
                    "role": "system",
                    "content": systemInstruction
                ],
                [
                    "role": "user",
                    "content": question,
                    "images": [imageBase64]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OllamaClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local Ollama daemon unreachable at 127.0.0.1:11434"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let rawText = message["content"] as? String else {
            throw NSError(domain: "OllamaClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from Ollama"])
        }

        return GeminiClient.shared.parseResponseText(rawText)
    }
}
