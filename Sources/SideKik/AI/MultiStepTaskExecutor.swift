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
               lower.contains(" and type ") ||
               lower.contains(" followed by ") ||
               lower.contains("after that") ||
               (lower.contains("open ") && lower.contains("type ")) ||
               (lower.contains("open ") && lower.contains("search ")) ||
               lower.contains("make the video") ||
               lower.contains("slow down") ||
               lower.contains("speed up")
    }

    /// Executes sequential steps, re-observing the screen after each UI transition or executing fast-path from memory
    public func executeSequence(goal: String, activeAppName: String, apiKey: String) async {
        // 1. Fast-Path Memory Check: If learned workflow exists, execute immediately in <1.2s!
        if let fastWorkflow = AppMemoryStore.shared.findWorkflow(forPrompt: goal) {
            print("Found learned workflow in memory for: \(fastWorkflow.intentKey)")
            let executed = await executeFastWorkflow(fastWorkflow, goal: goal)
            if executed {
                return
            }
        }

        AppState.shared.statusMessage = "Planning task..."
        AppState.shared.companionState = .thinking
        AppState.shared.activeTaskDescription = goal
        AppState.shared.activeTaskProgress = 0.1

        let startTime = Date()
        var history: [String] = []
        var recordedSteps: [WorkflowStep] = []
        var loggedActions: [LoggedAction] = []
        var usedLandmarks: [String] = []
        let maxSteps = 4

        for step in 1...maxSteps {
            AppState.shared.activeTaskProgress = Double(step) / Double(maxSteps)
            AppState.shared.statusMessage = "Step \(step): Analyzing screen..."

            // Fresh screen capture to observe current UI state
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
            let memorySummary = AppMemoryStore.shared.getLandmarksSummary(app: activeAppName)

            let prompt = """
            You are executing an autonomous multi-step GUI task on macOS.
            OVERALL USER GOAL: "\(goal)"
            CURRENT STEP: \(step) of \(maxSteps).
            PREVIOUS ACTIONS EXECUTED: \(historySummary)

            Spatial Memory Context for \(activeAppName):
            \(memorySummary)

            Inspect the current screen image carefully.
            Determine the NEXT PHYSICAL ACTION needed right now to progress toward the user's overall goal.
            - If the goal has been fully completed, tag: [DONE:Clear spoken confirmation]
            - If you need to click an element (menu item, icon, button, tab, clip): tag: [CLICK:x,y:Label]
            - If you need to type text: tag: [TYPE:text]
            - If you need to open an application: tag: [OPEN:AppName]
            - If you need to run a shell command: tag: [RUN:command]
            - If you need to scroll or scrub a timeline/canvas: tag: [SCROLL:dx,dy:Label]

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

                let label = response.targetLabel ?? "element"
                history.append("Clicked \(label) at (\(Int(norm.x)), \(Int(norm.y)))")
                recordedSteps.append(WorkflowStep(actionType: "click", target: label, normX: norm.x, normY: norm.y))
                loggedActions.append(LoggedAction(type: "click", target: label, x: norm.x, y: norm.y))
                usedLandmarks.append(label)

                // Remember landmark for fast recall
                AppMemoryStore.shared.rememberLandmark(app: activeAppName, key: label, x: norm.x, y: norm.y)

                // Wait for macOS UI transition (menu dropdown, modal opening, window focus)
                try? await Task.sleep(nanoseconds: 850_000_000)

                AppState.shared.targetPoint = nil
                AppState.shared.targetLabel = nil
            } else if case .typeText(let txt) = response.action {
                CompanionOrchestrator.shared.speak(response.spokenText)
                try? await Task.sleep(nanoseconds: 400_000_000)
                ActionController.shared.typeText(txt)
                history.append("Typed '\(txt)'")
                recordedSteps.append(WorkflowStep(actionType: "type", target: txt))
                loggedActions.append(LoggedAction(type: "type", details: txt))
                try? await Task.sleep(nanoseconds: 600_000_000)
            } else if case .openApp(let app) = response.action {
                CompanionOrchestrator.shared.speak(response.spokenText)
                _ = ActionController.shared.launchApplication(named: app)
                history.append("Opened \(app)")
                recordedSteps.append(WorkflowStep(actionType: "openApp", target: app))
                loggedActions.append(LoggedAction(type: "openApp", target: app))
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            } else if case .scroll(let dx, let dy, let label) = response.action {
                AppState.shared.statusMessage = "Scrolling \(label ?? "area")..."
                CompanionOrchestrator.shared.speak(response.spokenText)
                let scrollPoint = response.targetPointNormalized.map { norm in
                    let screenFrame = capture.screenFrame
                    return CGPoint(
                        x: screenFrame.origin.x + (norm.x / 1000.0) * screenFrame.width,
                        y: screenFrame.origin.y + (norm.y / 1000.0) * screenFrame.height
                    )
                }
                ActionController.shared.scroll(deltaX: dx, deltaY: dy, at: scrollPoint)
                history.append("Scrolled \(label ?? "area") by (dx: \(dx), dy: \(dy))")
                recordedSteps.append(WorkflowStep(actionType: "scroll", target: label, normX: Double(dx), normY: Double(dy)))
                loggedActions.append(LoggedAction(type: "scroll", target: label, details: "dx: \(dx), dy: \(dy)"))
                try? await Task.sleep(nanoseconds: 700_000_000)
            } else if case .runShell(let cmd) = response.action {
                CompanionOrchestrator.shared.speak(response.spokenText)
                _ = await ActionController.shared.executeShellCommand(cmd)
                history.append("Ran command: \(cmd)")
                loggedActions.append(LoggedAction(type: "runShell", details: cmd))
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

        // Cache the newly discovered workflow into memory for instant repeat runs
        if !recordedSteps.isEmpty {
            AppMemoryStore.shared.recordWorkflow(intent: goal, app: activeAppName, steps: recordedSteps)
        }

        let duration = Date().timeIntervalSince(startTime) * 1000.0
        InteractionLogger.shared.record(InteractionLogEntry(
            activeAppName: activeAppName,
            input: goal,
            mode: "multi_step_agent",
            output: AppState.shared.lastAIResponse,
            actions: loggedActions,
            landmarks: usedLandmarks,
            durationMs: duration,
            status: "success",
            diagnostics: "Executed \(loggedActions.count) actions over multi-step loop."
        ))

        // Final completion wrapping
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        AppState.shared.activeTaskDescription = nil
        AppState.shared.activeTaskProgress = nil
        if AppState.shared.companionState != .speaking {
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "Ready"
        }
    }

    /// Fast-path memory execution: executes learned steps directly without calling slow vision API
    private func executeFastWorkflow(_ workflow: LearnedWorkflow, goal: String) async -> Bool {
        AppState.shared.statusMessage = "Executing from memory for \(workflow.appName)..."
        AppState.shared.companionState = .working
        AppState.shared.activeTaskDescription = goal
        AppState.shared.activeTaskProgress = 0.2

        var textToType: String? = nil
        let lowerGoal = goal.lowercased()
        if let range = lowerGoal.range(of: "type ") {
            textToType = String(goal[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for (idx, step) in workflow.steps.enumerated() {
            AppState.shared.activeTaskProgress = Double(idx + 1) / Double(workflow.steps.count)

            switch step.actionType {
            case "openApp":
                let app = step.target ?? workflow.appName
                _ = ActionController.shared.launchApplication(named: app)
                try? await Task.sleep(nanoseconds: UInt64((step.delayMs ?? 700) * 1_000_000))

            case "click":
                let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let nx = step.normX ?? 500.0
                let ny = step.normY ?? 500.0
                let targetX = screenFrame.origin.x + (nx / 1000.0) * screenFrame.width
                let targetY = screenFrame.origin.y + (ny / 1000.0) * screenFrame.height

                AppState.shared.targetPoint = CGPoint(x: targetX, y: targetY)
                AppState.shared.targetLabel = step.target ?? "Landmark"
                AppState.shared.companionState = .pointing

                try? await Task.sleep(nanoseconds: 300_000_000)
                ActionController.shared.click(at: CGPoint(x: targetX, y: targetY), targetAppName: nil)
                try? await Task.sleep(nanoseconds: UInt64((step.delayMs ?? 400) * 1_000_000))
                AppState.shared.targetPoint = nil

            case "type":
                if let txt = textToType, !txt.isEmpty {
                    ActionController.shared.typeText(txt)
                    try? await Task.sleep(nanoseconds: UInt64((step.delayMs ?? 250) * 1_000_000))
                } else if let fallback = step.target {
                    ActionController.shared.typeText(fallback)
                    try? await Task.sleep(nanoseconds: UInt64((step.delayMs ?? 250) * 1_000_000))
                }

            case "return":
                ActionController.shared.pressReturn()
                try? await Task.sleep(nanoseconds: UInt64((step.delayMs ?? 150) * 1_000_000))

            case "scroll":
                ActionController.shared.scroll(deltaX: Int32(step.normX ?? 0), deltaY: Int32(step.normY ?? -5))
                try? await Task.sleep(nanoseconds: UInt64((step.delayMs ?? 500) * 1_000_000))

            default:
                break
            }
        }

        AppState.shared.companionState = .happy
        AppState.shared.statusMessage = "Done! (From Memory)"
        let confirmation = "Done! Executed \(workflow.appName) workflow from memory."
        AppState.shared.lastAIResponse = confirmation
        CompanionOrchestrator.shared.speak(confirmation)

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        AppState.shared.activeTaskDescription = nil
        AppState.shared.activeTaskProgress = nil
        if AppState.shared.companionState != .speaking {
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "Ready"
        }
        return true
    }
}
