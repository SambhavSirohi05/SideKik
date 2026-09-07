import Foundation
import Network
import AppKit

/// Lightweight local loopback HTTP server (127.0.0.1:25425) for agent IPC notifications
public final class AgentNotificationServer: @unchecked Sendable {
    public static let shared = AgentNotificationServer()
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 25425

    private init() {}

    public func start() {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: port)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("AgentNotificationServer running on http://127.0.0.1:25425")
                case .failed(let error):
                    print("AgentNotificationServer failed to bind: \(error)")
                default:
                    break
                }
            }

            listener?.start(queue: DispatchQueue.global(qos: .userInitiated))
        } catch {
            print("Failed to start AgentNotificationServer: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        receiveData(from: connection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, !data.isEmpty else {
                connection.cancel()
                return
            }

            self.processHTTPRequest(data: data, connection: connection)
        }
    }

    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(status: "400 Bad Request", body: "{\"error\":\"Invalid UTF-8\"}", connection: connection)
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(status: "400 Bad Request", body: "{\"error\":\"Empty request\"}", connection: connection)
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(status: "400 Bad Request", body: "{\"error\":\"Malformed request line\"}", connection: connection)
            return
        }

        let method = parts[0].uppercased()
        let path = parts[1]

        // Extract JSON body
        var bodyData = Data()
        if let bodyIndex = requestString.range(of: "\r\n\r\n") {
            let bodySubstring = requestString[bodyIndex.upperBound...]
            bodyData = Data(bodySubstring.utf8)
        }

        if method == "POST" && (path == "/attention" || path == "/notify") {
            handleAttentionRequest(bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/react" {
            handleReactRequest(bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/say" {
            handleSayRequest(bodyData: bodyData, connection: connection)
        } else {
            sendResponse(status: "200 OK", body: "{\"status\":\"SideKik Agent Bridge Active\",\"port\":25425}", connection: connection)
        }
    }

    private func handleAttentionRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(status: "400 Bad Request", body: "{\"error\":\"Invalid JSON\"}", connection: connection)
            return
        }

        let appName = (json["app"] as? String) ?? (json["appName"] as? String) ?? "Agent"
        let title = (json["title"] as? String) ?? "Agent Needs Input"
        let message = (json["message"] as? String) ?? "\(appName) is waiting for your input."

        Task { @MainActor in
            let windowFrame = AccessibilityManager.shared.findWindowFrame(forAppName: appName)
            let alert = AgentAlert(appName: appName, title: title, message: message, windowFrame: windowFrame)

            AppState.shared.setAlert(alert)
            NSSound(named: "Tink")?.play()

            // If window frame was found, position companion near it
            if let frame = windowFrame {
                AppState.shared.targetPoint = CGPoint(x: frame.midX, y: frame.maxY - 40)
                AppState.shared.targetLabel = "\(appName) Prompt"
            }
        }

        sendResponse(status: "200 OK", body: "{\"status\":\"alert_triggered\",\"app\":\"\(appName)\"}", connection: connection)
    }

    private func handleReactRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let stateString = json["state"] as? String,
              let newState = CompanionState(rawValue: stateString.lowercased()) else {
            sendResponse(status: "400 Bad Request", body: "{\"error\":\"Invalid state\"}", connection: connection)
            return
        }

        Task { @MainActor in
            AppState.shared.companionState = newState
        }
        sendResponse(status: "200 OK", body: "{\"status\":\"state_updated\"}", connection: connection)
    }

    private func handleSayRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let text = json["text"] as? String else {
            sendResponse(status: "400 Bad Request", body: "{\"error\":\"Missing text\"}", connection: connection)
            return
        }

        let voice = (json["voice"] as? Bool) ?? true

        Task { @MainActor in
            AppState.shared.lastAIResponse = text
            AppState.shared.companionState = .speaking
            if voice {
                NativeSpeechFallback.shared.speak(text: text) {
                    Task { @MainActor in
                        if AppState.shared.companionState == .speaking {
                            AppState.shared.companionState = .idle
                        }
                    }
                }
            }
        }
        sendResponse(status: "200 OK", body: "{\"status\":\"speaking\"}", connection: connection)
    }

    private func sendResponse(status: String, body: String, connection: NWConnection) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r
        \(body)
        """
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }
}
