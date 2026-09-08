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
        } else if method == "POST" && (path == "/ask" || path == "/interact" || path == "/test") {
            handleAskRequest(bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/interrupt" {
            Task { @MainActor in
                CompanionOrchestrator.shared.interruptSpeech(resumeListening: false)
                self.sendResponse(status: "200 OK", body: "{\"status\":\"interrupted\"}", connection: connection)
            }
        } else if method == "POST" && path == "/tour" {
            Task { @MainActor in
                CompanionOrchestrator.shared.startAppTour()
                self.sendResponse(status: "200 OK", body: "{\"status\":\"tour_started\"}", connection: connection)
            }
        } else if method == "POST" && path == "/next_step" {
            Task { @MainActor in
                CompanionOrchestrator.shared.nextTourStep()
                self.sendResponse(status: "200 OK", body: "{\"status\":\"next_step_triggered\"}", connection: connection)
            }
        } else if method == "POST" && path == "/prev_step" {
            Task { @MainActor in
                CompanionOrchestrator.shared.prevTourStep()
                self.sendResponse(status: "200 OK", body: "{\"status\":\"prev_step_triggered\"}", connection: connection)
            }
        } else if method == "POST" && path == "/toggle_pause" {
            Task { @MainActor in
                CompanionOrchestrator.shared.toggleTourPause()
                self.sendResponse(status: "200 OK", body: "{\"status\":\"pause_toggled\"}", connection: connection)
            }
        } else if method == "POST" && path == "/toggle_pet" {
            Task { @MainActor in
                AppState.shared.isPetEnabled.toggle()
                AppState.shared.saveConfig()
                self.sendResponse(status: "200 OK", body: "{\"isPetEnabled\":\(AppState.shared.isPetEnabled)}", connection: connection)
            }
        } else if method == "GET" && (path == "/log" || path == "/history") {
            let entries = InteractionLogger.shared.recentEntries(limit: 20)
            if let outData = try? JSONEncoder().encode(entries),
               let outStr = String(data: outData, encoding: .utf8) {
                self.sendResponse(status: "200 OK", body: outStr, connection: connection)
            } else {
                self.sendResponse(status: "200 OK", body: "[]", connection: connection)
            }
        } else if method == "GET" && (path == "/log/text" || path == "/logs") {
            let text = InteractionLogger.shared.formattedLog(limitLines: 150)
            self.sendResponse(status: "200 OK", body: text, contentType: "text/plain; charset=utf-8", connection: connection)
        } else if method == "GET" && path == "/state" {
            Task { @MainActor in
                let resJson: [String: Any] = [
                    "companionState": AppState.shared.companionState.rawValue,
                    "selectedPetId": AppState.shared.selectedPetId,
                    "isPetEnabled": AppState.shared.isPetEnabled,
                    "activeAppName": AppState.shared.activeAppName,
                    "isTourActive": AppState.shared.isTourActive,
                    "totalTourSteps": AppState.shared.totalTourSteps,
                    "currentTourStep": AppState.shared.currentTourStep,
                    "statusMessage": AppState.shared.statusMessage,
                    "lastAIResponse": AppState.shared.lastAIResponse,
                    "targetPoint": AppState.shared.targetPoint.map { ["x": $0.x, "y": $0.y] } as Any,
                    "targetLabel": AppState.shared.targetLabel as Any
                ]
                if let outData = try? JSONSerialization.data(withJSONObject: resJson),
                   let outStr = String(data: outData, encoding: .utf8) {
                    self.sendResponse(status: "200 OK", body: outStr, connection: connection)
                } else {
                    self.sendResponse(status: "200 OK", body: "{}", connection: connection)
                }
            }
        } else {
            sendResponse(status: "200 OK", body: "{\"status\":\"SideKik Agent Bridge Active\",\"port\":25425}", connection: connection)
        }
    }

    private func handleAskRequest(bodyData: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let question = (json["question"] as? String) ?? (json["prompt"] as? String) else {
            sendResponse(status: "400 Bad Request", body: "{\"error\":\"Missing question or prompt\"}", connection: connection)
            return
        }

        Task { @MainActor in
            await CompanionOrchestrator.shared.processInteraction(audioData: nil, typedPrompt: question)
            let resJson: [String: Any] = [
                "status": "success",
                "state": AppState.shared.companionState.rawValue,
                "isTourActive": AppState.shared.isTourActive,
                "totalTourSteps": AppState.shared.totalTourSteps,
                "currentTourStep": AppState.shared.currentTourStep,
                "targetPoint": AppState.shared.targetPoint.map { ["x": $0.x, "y": $0.y] } as Any,
                "targetLabel": AppState.shared.targetLabel as Any,
                "lastAIResponse": AppState.shared.lastAIResponse,
                "statusMessage": AppState.shared.statusMessage
            ]
            if let outData = try? JSONSerialization.data(withJSONObject: resJson),
               let outStr = String(data: outData, encoding: .utf8) {
                self.sendResponse(status: "200 OK", body: outStr, connection: connection)
            } else {
                self.sendResponse(status: "200 OK", body: "{\"status\":\"processed\"}", connection: connection)
            }
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
            if voice {
                CompanionOrchestrator.shared.speak(text)
            } else {
                AppState.shared.companionState = .speaking
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if AppState.shared.companionState == .speaking {
                        AppState.shared.companionState = .idle
                    }
                }
            }
        }
        sendResponse(status: "200 OK", body: "{\"status\":\"speaking\"}", connection: connection)
    }

    private func sendResponse(status: String, body: String, contentType: String = "application/json", connection: NWConnection) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
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
