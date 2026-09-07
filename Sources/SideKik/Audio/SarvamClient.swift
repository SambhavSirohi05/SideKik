import Foundation

public enum SarvamError: Error, LocalizedError, Sendable {
    case missingApiKey
    case invalidRequest
    case networkError(String)
    case apiError(Int, String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Sarvam API subscription key is not configured."
        case .invalidRequest:
            return "Invalid request configuration."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "Sarvam API error (\(code)): \(msg)"
        case .decodingError(let msg):
            return "Failed to decode Sarvam response: \(msg)"
        }
    }
}

/// Async HTTP client communicating with Sarvam AI REST endpoints
public final class SarvamClient: Sendable {
    public static let shared = SarvamClient()
    private let session = URLSession.shared

    private init() {}

    /// Transcribes audio using Sarvam Saaras v4
    public func speechToText(audioWavData: Data, apiKey: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SarvamError.missingApiKey
        }

        guard let url = URL(string: "https://api.sarvam.ai/speech-to-text") else {
            throw SarvamError.invalidRequest
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        request.timeoutInterval = 15.0

        var body = Data()

        // Form field: model
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"model\"\r\n\r\n".utf8)
        body.append(contentsOf: "saaras:v4\r\n".utf8)

        // Form field: mode
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"mode\"\r\n\r\n".utf8)
        body.append(contentsOf: "transcribe\r\n".utf8)

        // Form field: language_code
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"language_code\"\r\n\r\n".utf8)
        body.append(contentsOf: "unknown\r\n".utf8)

        // Form field: file
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: audio/wav\r\n\r\n".utf8)
        body.append(audioWavData)
        body.append(contentsOf: "\r\n".utf8)

        // End boundary
        body.append(contentsOf: "--\(boundary)--\r\n".utf8)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SarvamError.networkError("Invalid HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SarvamError.apiError(httpResponse.statusCode, errorText)
        }

        struct STTResponse: Decodable {
            let transcript: String?
        }

        do {
            let decoded = try JSONDecoder().decode(STTResponse.self, from: data)
            return decoded.transcript ?? ""
        } catch {
            throw SarvamError.decodingError(error.localizedDescription)
        }
    }

    /// Synthesizes speech using Sarvam Bulbul v3, returning decoded audio Data
    public func textToSpeech(text: String, apiKey: String, speaker: String = "shubh", pace: Double = 1.05) async throws -> Data {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SarvamError.missingApiKey
        }

        guard let url = URL(string: "https://api.sarvam.ai/text-to-speech") else {
            throw SarvamError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        request.timeoutInterval = 15.0

        let payload: [String: Any] = [
            "inputs": [text],
            "target_language_code": "en-IN",
            "speaker": speaker,
            "pitch": 0,
            "pace": pace,
            "loudness": 1.0,
            "speech_sample_rate": 24000,
            "enable_preprocessing": true,
            "model": "bulbul:v3"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SarvamError.networkError("Invalid HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SarvamError.apiError(httpResponse.statusCode, errorText)
        }

        struct TTSResponse: Decodable {
            let audios: [String]?
        }

        do {
            let decoded = try JSONDecoder().decode(TTSResponse.self, from: data)
            guard let firstAudioBase64 = decoded.audios?.first,
                  let audioData = Data(base64Encoded: firstAudioBase64) else {
                throw SarvamError.decodingError("No valid base64 audio in response")
            }
            return audioData
        } catch {
            throw SarvamError.decodingError(error.localizedDescription)
        }
    }
}
