import Foundation
import AppKit
import CoreGraphics

/// Executes multi-step autonomous GUI tasks across dynamic UI transitions (HeyClicky-style agent loop)
@MainActor
public final class MultiStepTaskExecutor {
    public static let shared = MultiStepTaskExecutor()

    private init() {}

    /// Detects if a prompt contains sequential compound actions requiring an agent loop
    public func isMultiStepTask(prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return lower.contains(" and then ") ||
               lower.contains(" then ") ||
               lower.contains(" and click ") ||
               lower.contains(" and select ") ||
               lower.contains(" and open ") ||
               lower.contains(" followed by ") ||
               lower.contains("after that")
    }

    /// Executes sequential steps, re-observing the screen after each UI transition
    public func executeSequence(goal: String, activeAppName: String, apiKey: String) async {
        AppState.shared.statusMessage = "Planning task..."
        AppState.shared.companionState = .thinking
        AppState.shared.activeTaskDescription = goal
        AppState.shared.activeTaskProgress = 0.1

        var history: [String] = []
        let maxSteps = 4

        for step in 1...maxSteps {
            AppState.shared.activeTaskProgress = Double(step) / Double(maxSteps)
            AppState.shared.statusMessage = "Step \(step): Analyzing screen..."

            // 1. Fresh screen capture to observe current UI state
            var screenResult: ScreenCaptureResult? = nil
            do {
                screenResult = try await ScreenCaptureManager.shared.captureActiveDisplay()
            } catch {
                print("Multi-step capture error at step \(step): \(error)")
            }

            guard let capture = screenResult else {
                AppState.shared.companionState = .error
                AppState.shared.statusMessage = "Screen capture failed"
                CompanionOrchestrator.shared.speak("I lost sight of the screen during step \(step).")
                break
            }

            let historySummary = history.isEmpty ? "None (initial state)" : history.joined(separator: " -> ")

            let prompt = """
            You are executing an autonomous multi-step GUI task on macOS.
            OVERALL USER GOAL: "\(goal)"
            CURRENT STEP: \(step) of \(maxSteps).
            PREVIOUS ACTIONS EXECUTED: \(historySummary)

            Inspect the current screen image carefully.
            Determine the NEXT PHYSICAL ACTION needed right now to progress toward the user's overall goal.
            - If the goal has been fully completed (e.g. the final item was already clicked or opened), tag: [DONE:Clear spoken confirmation]
            - If you need to click an element (e.g. Apple logo, menu item, icon, button, tab): tag: [CLICK:x,y:Label]
            - If you need to type text: tag: [TYPE:text]
            - If you need to open an application: tag: [OPEN:AppName]
            - If you need to run a shell command: tag: [RUN:command]

            macOS Menu Guidelines:
            - Apple logo: (x ~ 15, y ~ 12). Clicking it opens the Apple dropdown menu.
            - When the Apple dropdown is open: it extends from (x ~ 10, y ~ 30) downwards. "Force Quit..." is located inside the menu at (x ~ 70, y ~ 150..165).
            - Always pinpoint the EXACT CENTER of the target element.

            State in 1 concise spoken sentence what you are doing in this step.
            """

            var aiResponse: AIResponse? = nil
            do {
                aiResponse = try await GeminiClient.shared.analyzeScreen(
                    question: prompt,
                    imageBase64: capture.imageBase64,
                    activeAppName: activeAppName,
                    apiKey: apiKey
                )
            } catch {
                print("Gemini inference error in multi-step executor: \(error)")
                break
            }

            guard let response = aiResponse else { break }

            // Check if task is finished
            if case .done(let summary) = response.action {
                AppState.shared.companionState = .happy
                AppState.shared.statusMessage = "Task Complete!"
                AppState.shared.activeTaskProgress = 1.0
                let speech = summary.isEmpty ? "All done! I finished \(goal) for you." : summary
                AppState.shared.lastAIResponse = speech
                CompanionOrchestrator.shared.speak(speech)
                break
            }

            // Execute the action for this step
            if let norm = response.targetPointNormalized {
                let screenFrame = capture.screenFrame
                let screenX = screenFrame.origin.x + (norm.x / 1000.0) * screenFrame.width
                let screenY = screenFrame.origin.y + (norm.y / 1000.0) * screenFrame.height

                AppState.shared.targetPoint = CGPoint(x: screenX, y: screenY)
                AppState.shared.targetLabel = response.targetLabel ?? "Step \(step)"
                AppState.shared.companionState = .pointing
                AppState.shared.lastAIResponse = response.spokenText
                AppState.shared.statusMessage = "Step \(step): \(response.targetLabel ?? "Acting")"

                CompanionOrchestrator.shared.speak(response.spokenText)

                // Brief glide delay before physical click
                try? await Task.sleep(nanoseconds: 650_000_000)

                let clickTarget = CGPoint(x: screenX, y: screenY)
                ActionController.shared.click(at: clickTarget, targetAppName: nil)

                history.append("Clicked \(response.targetLabel ?? "element") at (\(Int(norm.x)), \(Int(norm.y)))")

                // Wait for macOS UI transition (menu dropdown, modal opening, window focus)
                try? await Task.sleep(nanoseconds: 850_000_000)

                AppState.shared.targetPoint = nil
                AppState.shared.targetLabel = nil
            } else if case .typeText(let txt) = response.action {
                CompanionOrchestrator.shared.speak(response.spokenText)
                try? await Task.sleep(nanoseconds: 400_000_000)
                ActionController.shared.typeText(txt)
                history.append("Typed '\(txt)'")
                try? await Task.sleep(nanoseconds: 600_000_000)
            } else if case .openApp(let app) = response.action {
                CompanionOrchestrator.shared.speak(response.spokenText)
                _ = ActionController.shared.launchApplication(named: app)
                history.append("Opened \(app)")
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            } else if case .runShell(let cmd) = response.action {
                CompanionOrchestrator.shared.speak(response.spokenText)
                _ = await ActionController.shared.executeShellCommand(cmd)
                history.append("Ran command: \(cmd)")
                try? await Task.sleep(nanoseconds: 800_000_000)
            } else {
                // If no actionable tag, speak the response and end
                CompanionOrchestrator.shared.speak(response.spokenText)
                break
            }

            // If we have executed the apparent final action of a 2-step compound prompt
            if step == 2 && !goal.contains("then click") && !goal.contains("and then") {
                AppState.shared.companionState = .happy
                AppState.shared.statusMessage = "Done!"
                break
            }
        }

        // Final completion wrapping
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        AppState.shared.activeTaskDescription = nil
        AppState.shared.activeTaskProgress = nil
        if AppState.shared.companionState != .speaking {
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "Ready"
        }
    }
}
