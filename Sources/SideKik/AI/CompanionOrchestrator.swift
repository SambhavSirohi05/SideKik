import Foundation
import AppKit
import SwiftUI

/// Coordinates Audio, Multimodal Screen Vision (Gemini), Action Execution, and Desktop Tours
@MainActor
public final class CompanionOrchestrator: ObservableObject {
    public static let shared = CompanionOrchestrator()

    private var isProcessing = false
    private var tourSteps: [TourStep] = []
    private var tourScreenFrame: NSRect = .zero
    private var tourCurrentIndex: Int = 0

    private init() {}

    // MARK: - Push-to-Talk & Speech Interruptibility

    /// Triggered when the push-to-talk hotkey is pressed or voice button is clicked
    public func startPushToTalk() {
        // If companion is speaking or running a tour: cut voice immediately and start listening!
        if AppState.shared.companionState == .speaking || AppState.shared.isTourActive || AudioManager.shared.isPlaying {
            interruptSpeech(resumeListening: true)
            return
        }

        guard AppState.shared.companionState == .idle || AppState.shared.companionState == .alert else { return }

        do {
            try AudioManager.shared.startRecording()
            AppState.shared.companionState = .listening
            AppState.shared.statusMessage = "Listening..."
            AppState.shared.clearAlert()
        } catch {
            print("Failed to start audio capture: \(error)")
            AppState.shared.statusMessage = "Microphone error: \(error.localizedDescription)"
        }
    }

    /// Triggered when the push-to-talk hotkey is released
    public func stopPushToTalk() {
        guard AppState.shared.companionState == .listening else { return }

        AppState.shared.companionState = .thinking
        AppState.shared.statusMessage = "Thinking..."

        let audioWavData = AudioManager.shared.stopRecording()

        Task {
            await processInteraction(audioData: audioWavData)
        }
    }

    /// Cuts speech instantly mid-sentence, optionally transitioning immediately to listening mode
    public func interruptSpeech(resumeListening: Bool = false) {
        AudioManager.shared.stopAudio(notifyCompletion: false)
        cancelTour()

        InteractionLogger.shared.record(InteractionLogEntry(
            activeAppName: AppState.shared.activeAppName,
            input: "[USER_INTERRUPT]",
            mode: "interrupt",
            output: "Cut speech mid-sentence",
            actions: [LoggedAction(type: "interruptSpeech", details: "resumeListening: \(resumeListening)")],
            status: "interrupted"
        ))

        if resumeListening {
            do {
                try AudioManager.shared.startRecording()
                AppState.shared.companionState = .listening
                AppState.shared.statusMessage = "Listening..."
                AppState.shared.clearAlert()
            } catch {
                AppState.shared.statusMessage = "Microphone error: \(error.localizedDescription)"
            }
        } else {
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "Ready"
            AppState.shared.targetPoint = nil
            AppState.shared.targetLabel = nil
            AppState.shared.lastAIResponse = ""
        }
    }

    // MARK: - Interaction Flow

    /// Executes end-to-end multi-modal flow
    public func processInteraction(audioData: Data?, typedPrompt: String? = nil) async {
        let interactionStartTime = Date()
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // 1. Privacy Guard Check
        let privacyCheck = PrivacyGuard.shared.validateScreenCapture()
        guard privacyCheck.isAllowed else {
            AppState.shared.companionState = .alert
            AppState.shared.statusMessage = "Screen masked: \(privacyCheck.reason ?? "Privacy")"
            speak("I cannot inspect the screen right now because a protected window is active.")
            return
        }

        let activeApp = privacyCheck.appName
        AppState.shared.activeAppName = activeApp

        // 2. Transcribe Audio (or use typed prompt)
        var userQuestion = typedPrompt ?? ""
        if userQuestion.isEmpty, let wav = audioData, !wav.isEmpty {
            let sarvamKey = AppState.shared.sarvamApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sarvamKey.isEmpty {
                do {
                    AppState.shared.statusMessage = "Transcribing with Sarvam..."
                    userQuestion = try await SarvamClient.shared.speechToText(audioWavData: wav, apiKey: sarvamKey)
                } catch {
                    print("Sarvam STT failed: \(error), falling back to default question")
                    userQuestion = "What is on my screen and where should I look?"
                }
            } else {
                userQuestion = "What is on my screen and what should I click?"
            }
        }

        userQuestion = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userQuestion.isEmpty else {
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "No speech detected"
            return
        }

        AppState.shared.lastSpokenTranscript = userQuestion

        // Check if user is asking for a background task
        if isBackgroundTaskRequest(userQuestion) {
            WorkerManager.shared.spawnTask(title: "Autonomous Agent Task", brief: userQuestion)
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "background_task",
                output: "Spawned background agent task",
                actions: [LoggedAction(type: "spawnTask", target: "Autonomous Agent Task", details: userQuestion)],
                durationMs: duration,
                status: "success"
            ))
            return
        }

        let geminiKey = AppState.shared.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if user request matches a learned workflow in memory (Instant <1.2s Fast-Path)
        if AppMemoryStore.shared.findWorkflow(forPrompt: userQuestion) != nil {
            await MultiStepTaskExecutor.shared.executeSequence(
                goal: userQuestion,
                activeAppName: activeApp,
                apiKey: geminiKey
            )
            return
        }

        // Check if user is asking for an autonomous multi-step GUI sequence (e.g. click Apple logo then click Force Quit)
        if MultiStepTaskExecutor.shared.isMultiStepTask(prompt: userQuestion) {
            guard !geminiKey.isEmpty else {
                speak("Please add your Google Gemini API key in Settings to enable multi-step actions.")
                return
            }
            await MultiStepTaskExecutor.shared.executeSequence(
                goal: userQuestion,
                activeAppName: activeApp,
                apiKey: geminiKey
            )
            return
        }

        // Detect if user query is asking for a tutorial / tour (robust to spacing/typos like "walkmethrough")
        let lowerQ = userQuestion.lowercased()
        let cleanNoSpaces = lowerQ.replacingOccurrences(of: " ", with: "")
        let isTourQuery = lowerQ.contains("tour") ||
                          lowerQ.contains("teach") ||
                          cleanNoSpaces.contains("walkthrough") ||
                          cleanNoSpaces.contains("walkmethrough") ||
                          lowerQ.contains("walk me") ||
                          lowerQ.contains("how do i use") ||
                          lowerQ.contains("explain this") ||
                          lowerQ.contains("show me around") ||
                          lowerQ.contains("guide me")

        var promptToSend = userQuestion
        if isTourQuery {
            promptToSend += "\n\nCRITICAL TOUR REQUIREMENT: The user requested a guided walkthrough of \(activeApp). You MUST output 1 friendly intro sentence, followed immediately by at least 4 [STEP:x,y:Zone Name:Narration] tags targeting distinct zones across the screen (Header, Sidebar, Workspace, Utility). Do NOT just offer to walk through; you must output the [STEP:...] tags in your response right now."
        }

        // 3. Screen Capture via ScreenCaptureKit
        AppState.shared.statusMessage = "Analyzing screen..."
        var screenResult: ScreenCaptureResult? = nil
        do {
            screenResult = try await ScreenCaptureManager.shared.captureActiveDisplay()
        } catch {
            print("Screen capture failed: \(error)")
        }

        guard let capture = screenResult else {
            AppState.shared.companionState = .error
            AppState.shared.statusMessage = "Screen capture failed"
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "screen_capture",
                output: "Screen capture failed",
                durationMs: duration,
                status: "error",
                diagnostics: "Screen capture failed. Check Screen Recording permissions in System Settings."
            ))
            speak("I couldn't capture the screen. Please verify Screen Recording permissions in System Settings.")
            return
        }

        // 4. Multimodal Vision Reasoning (Google Gemini)
        var aiResponse: AIResponse? = nil

        if !geminiKey.isEmpty {
            do {
                aiResponse = try await GeminiClient.shared.analyzeScreen(
                    question: promptToSend,
                    imageBase64: capture.imageBase64,
                    activeAppName: activeApp,
                    apiKey: geminiKey
                )
            } catch {
                print("Gemini inference error: \(error)")
                aiResponse = AIResponse(
                    spokenText: "I encountered an error connecting to Gemini. \(error.localizedDescription)",
                    rawText: error.localizedDescription
                )
            }
        } else {
            aiResponse = AIResponse(
                spokenText: "I see \(activeApp) on your screen! Please add your free Google AI Studio API key in the menu bar to enable full visual reasoning.",
                rawText: "Please add your API key in Settings."
            )
        }

        guard let result = aiResponse else {
            AppState.shared.companionState = .error
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "gemini_vision",
                output: "No AI response returned",
                durationMs: duration,
                status: "error",
                diagnostics: "Gemini client returned nil response"
            ))
            return
        }

        AppState.shared.lastAIResponse = result.spokenText

        // 5. Multi-Step Interactive Guided Tour (Desktop Tutor Mode)
        if let tour = result.tourSteps, tour.count >= 3 {
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            let actions = tour.map { step in
                let norm = step.pointNormalized
                let screenX = capture.screenFrame.origin.x + (norm.x / 1000.0) * capture.screenFrame.width
                let screenY = capture.screenFrame.origin.y + (norm.y / 1000.0) * capture.screenFrame.height
                return LoggedAction(type: "tourStep", target: step.label, x: screenX, y: screenY, details: step.narration)
            }
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "tour",
                output: result.spokenText,
                rawOutput: result.rawText,
                actions: actions,
                landmarks: tour.map { $0.label },
                durationMs: duration,
                status: "success"
            ))
            Task { @MainActor in
                await self.executeTour(steps: tour, screenFrame: capture.screenFrame, introText: result.spokenText)
            }
            return
        } else if isTourQuery {
            // GUARANTEED WALKTHROUGH: Always ensure a rich 4-5 milestone tour across the entire app interface
            var combinedSteps = result.tourSteps ?? []
            let fallbackSteps = synthesizeFallbackTour(forApp: activeApp)
            if combinedSteps.isEmpty {
                combinedSteps = fallbackSteps
            } else {
                for fb in fallbackSteps {
                    if !combinedSteps.contains(where: { $0.label.lowercased() == fb.label.lowercased() }) {
                        combinedSteps.append(fb)
                    }
                }
            }
            let intro = result.spokenText.isEmpty ? "Welcome to \(activeApp)! Here is a guided walkthrough of the workspace:" : result.spokenText
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            let actions = combinedSteps.map { step in
                let norm = step.pointNormalized
                let screenX = capture.screenFrame.origin.x + (norm.x / 1000.0) * capture.screenFrame.width
                let screenY = capture.screenFrame.origin.y + (norm.y / 1000.0) * capture.screenFrame.height
                return LoggedAction(type: "tourStep", target: step.label, x: screenX, y: screenY, details: step.narration)
            }
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "tour_fallback",
                output: intro,
                rawOutput: result.rawText,
                actions: actions,
                landmarks: combinedSteps.map { $0.label },
                durationMs: duration,
                status: "success"
            ))
            Task { @MainActor in
                await self.executeTour(steps: combinedSteps, screenFrame: capture.screenFrame, introText: intro)
            }
            return
        }

        // 6. Calculate Cocoa Coordinates from Normalized Vision Points
        var targetCocoaX: Double = 0
        var targetCocoaY: Double = 0
        var hasTargetPoint = false

        if let norm = result.targetPointNormalized {
            let screenFrame = capture.screenFrame
            let screenX = screenFrame.origin.x + (norm.x / 1000.0) * screenFrame.width
            let screenY = screenFrame.origin.y + (norm.y / 1000.0) * screenFrame.height

            targetCocoaX = screenX
            targetCocoaY = screenY
            hasTargetPoint = true

            AppState.shared.targetPoint = CGPoint(x: screenX, y: screenY)
            AppState.shared.targetLabel = result.targetLabel ?? "Target"
            AppState.shared.companionState = .pointing
        }

        // 6. Log to Local SQLite Journal
        JournalDatabase.shared.insertEntry(
            appName: activeApp,
            question: userQuestion,
            answer: result.spokenText,
            targetX: targetCocoaX,
            targetY: targetCocoaY
        )

        // Automatically remember landmark in AppMemoryStore for instant future recall
        if hasTargetPoint, let label = result.targetLabel, let norm = result.targetPointNormalized {
            AppMemoryStore.shared.rememberLandmark(app: activeApp, key: label, x: norm.x, y: norm.y)
        }

        // 7. Resolve Actions (Tag-based or User Direct Intent)
        let (resolvedAction, spokenText) = resolveAction(from: result, question: userQuestion)
        let shouldAutoClick = (resolvedAction == .click) ||
                              AppState.shared.autoClick ||
                              (hasTargetPoint && (lowerQ.hasPrefix("click") || lowerQ.contains("click it") || lowerQ.contains("click on") || lowerQ.contains("tap")))

        if shouldAutoClick && hasTargetPoint {
            let clickTarget = CGPoint(x: targetCocoaX, y: targetCocoaY)
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "click",
                output: spokenText,
                rawOutput: result.rawText,
                actions: [
                    LoggedAction(type: "click", target: result.targetLabel ?? "target", x: targetCocoaX, y: targetCocoaY, details: "autoClick: \(shouldAutoClick)")
                ],
                landmarks: result.targetLabel != nil ? [result.targetLabel!] : [],
                durationMs: duration,
                status: "success"
            ))
            speak(spokenText)
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                ActionController.shared.click(at: clickTarget, targetAppName: activeApp)
                AppState.shared.companionState = .happy
                AppState.shared.statusMessage = "Clicked \(result.targetLabel ?? "target")!"
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                AppState.shared.targetPoint = nil
                AppState.shared.targetLabel = nil
                AppState.shared.companionState = .idle
                AppState.shared.statusMessage = "Ready"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                AppState.shared.lastAIResponse = ""
            }
            return
        }

        if case .openApp(let appToOpen) = resolvedAction {
            let success = ActionController.shared.launchApplication(named: appToOpen)
            AppState.shared.statusMessage = success ? "Opened \(appToOpen)" : "Could not open \(appToOpen)"
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "openApp",
                output: spokenText,
                rawOutput: result.rawText,
                actions: [LoggedAction(type: "openApp", target: appToOpen, details: "success: \(success)")],
                durationMs: duration,
                status: success ? "success" : "error",
                diagnostics: success ? nil : "Failed to launch application \(appToOpen)"
            ))
            speak(spokenText)
            return
        }

        if case .runShell(let cmd) = resolvedAction {
            AppState.shared.statusMessage = "Running command..."
            let output = await ActionController.shared.executeShellCommand(cmd)
            let speech = spokenText.isEmpty ? "Command executed." : spokenText
            AppState.shared.lastAIResponse = "\(speech)\n\n$ \(cmd)\n\(output)"
            AppState.shared.statusMessage = "Completed"
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "runShell",
                output: speech,
                rawOutput: output,
                actions: [LoggedAction(type: "runShell", details: cmd)],
                durationMs: duration,
                status: "success"
            ))
            speak(speech)
            return
        }

        if case .typeText(let txt) = resolvedAction {
            ActionController.shared.typeText(txt)
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "typeText",
                output: spokenText,
                rawOutput: result.rawText,
                actions: [LoggedAction(type: "typeText", details: txt)],
                durationMs: duration,
                status: "success"
            ))
            speak(spokenText)
            return
        }

        if case .scroll(let dx, let dy, let label) = resolvedAction {
            AppState.shared.statusMessage = "Scrolling \(label ?? "area")..."
            let scrollPoint = hasTargetPoint ? CGPoint(x: targetCocoaX, y: targetCocoaY) : nil
            ActionController.shared.scroll(deltaX: dx, deltaY: dy, at: scrollPoint)
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "scroll",
                output: spokenText,
                rawOutput: result.rawText,
                actions: [LoggedAction(type: "scroll", target: label, x: scrollPoint.map { Double($0.x) }, y: scrollPoint.map { Double($0.y) }, details: "dx: \(dx), dy: \(dy)")],
                durationMs: duration,
                status: "success"
            ))
            speak(spokenText)
            return
        }

        // 8. Visual Guidance Pointing (Beacon highlight & cursor flight)
        if hasTargetPoint {
            let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
            InteractionLogger.shared.record(InteractionLogEntry(
                activeAppName: activeApp,
                input: userQuestion,
                mode: "point",
                output: spokenText,
                rawOutput: result.rawText,
                actions: [LoggedAction(type: "point", target: result.targetLabel ?? "target", x: targetCocoaX, y: targetCocoaY)],
                landmarks: result.targetLabel != nil ? [result.targetLabel!] : [],
                durationMs: duration,
                status: "success"
            ))
            speak(spokenText) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    if AppState.shared.companionState == .pointing {
                        AppState.shared.targetPoint = nil
                        AppState.shared.targetLabel = nil
                        AppState.shared.companionState = .idle
                        AppState.shared.statusMessage = "Ready"
                        AppState.shared.lastAIResponse = ""
                    }
                }
            }
            return
        }

        // 9. General Spoken Response via Sarvam AI
        let duration = Date().timeIntervalSince(interactionStartTime) * 1000.0
        InteractionLogger.shared.record(InteractionLogEntry(
            activeAppName: activeApp,
            input: userQuestion,
            mode: "conversation",
            output: spokenText,
            rawOutput: result.rawText,
            durationMs: duration,
            status: "success"
        ))
        speak(spokenText)
    }

    /// Resolves action intents from Gemini structured tags or direct user query phrasing
    private func resolveAction(from result: AIResponse, question: String) -> (AIActionType?, String) {
        if let explicitAction = result.action {
            return (explicitAction, result.spokenText)
        }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.contains("scroll down") {
            let speech = result.spokenText.isEmpty ? "Scrolling down." : result.spokenText
            return (.scroll(0, -8, "down"), speech)
        } else if lower.contains("scroll up") {
            let speech = result.spokenText.isEmpty ? "Scrolling up." : result.spokenText
            return (.scroll(0, 8, "up"), speech)
        } else if lower.contains("scroll right") || lower.contains("scrub timeline") || lower.contains("scrub forward") {
            let speech = result.spokenText.isEmpty ? "Scrubbing timeline forward." : result.spokenText
            return (.scroll(10, 0, "timeline"), speech)
        } else if lower.contains("scroll left") || lower.contains("scrub backward") {
            let speech = result.spokenText.isEmpty ? "Scrubbing timeline backward." : result.spokenText
            return (.scroll(-10, 0, "timeline"), speech)
        } else if lower == "scroll" || lower.hasPrefix("scroll ") {
            let speech = result.spokenText.isEmpty ? "Scrolling down." : result.spokenText
            return (.scroll(0, -8, "screen"), speech)
        }

        if lower.hasPrefix("open ") {
            let appName = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !appName.isEmpty {
                let speech = result.spokenText.isEmpty ? "Opening \(appName) for you." : result.spokenText
                return (.openApp(appName), speech)
            }
        } else if lower.hasPrefix("launch ") {
            let appName = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !appName.isEmpty {
                let speech = result.spokenText.isEmpty ? "Launching \(appName) for you." : result.spokenText
                return (.openApp(appName), speech)
            }
        }

        if lower.hasPrefix("run ") {
            let cmd = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cmd.isEmpty {
                return (.runShell(cmd), result.spokenText)
            }
        } else if lower.hasPrefix("exec ") {
            let cmd = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cmd.isEmpty {
                return (.runShell(cmd), result.spokenText)
            }
        } else if lower.hasPrefix("execute ") {
            let cmd = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cmd.isEmpty {
                return (.runShell(cmd), result.spokenText)
            }
        }

        if lower.hasPrefix("click") || lower.contains("click it") || lower.contains("click on") || lower.contains("tap ") {
            return (.click, result.spokenText)
        }

        return (nil, result.spokenText)
    }

    /// Speaks text using Sarvam AI Bulbul v3 with zero robotic native voice
    public func speak(_ text: String, completion: (@Sendable () -> Void)? = nil) {
        AppState.shared.companionState = (AppState.shared.targetPoint != nil ? .pointing : .speaking)
        AppState.shared.statusMessage = "Speaking..."

        let sarvamKey = AppState.shared.sarvamApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sarvamKey.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.finishSpeaking()
                completion?()
            }
            return
        }

        Task {
            do {
                let audioData = try await SarvamClient.shared.textToSpeech(
                    text: text,
                    apiKey: sarvamKey,
                    speaker: AppState.shared.selectedVoice,
                    pace: AppState.shared.speechPace
                )
                AudioManager.shared.playAudio(data: audioData) { [weak self] in
                    Task { @MainActor in
                        self?.finishSpeaking()
                        completion?()
                    }
                }
            } catch {
                print("Sarvam TTS failed: \(error.localizedDescription)")
                finishSpeaking()
                completion?()
            }
        }
    }

    private func finishSpeaking() {
        if AppState.shared.companionState == .speaking {
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "Ready"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if AppState.shared.companionState == .idle {
                    AppState.shared.lastAIResponse = ""
                }
            }
        }
    }

    // MARK: - Desktop Tutor (Multi-Step Guided Tour)

    /// Triggers an interactive tour of the active application
    public func startAppTour() {
        interruptSpeech(resumeListening: false)
        AppState.shared.statusMessage = "Preparing tour..."
        let app = AppState.shared.activeAppName
        Task {
            await processInteraction(
                audioData: nil,
                typedPrompt: "Teach me how to use \(app) and give me a full 4 to 6 milestone guided tour of all its functional areas"
            )
        }
    }

    /// Executes a multi-step interactive guided tour across the screen
    public func executeTour(steps: [TourStep], screenFrame: NSRect, introText: String) async {
        self.tourSteps = steps
        self.tourScreenFrame = screenFrame
        self.tourCurrentIndex = 0

        AppState.shared.isTourActive = true
        AppState.shared.isTourPaused = false
        AppState.shared.totalTourSteps = steps.count
        AppState.shared.activeTourSteps = steps
        AppState.shared.currentTourStep = 1

        if !introText.isEmpty {
            speak(introText) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, AppState.shared.isTourActive, !AppState.shared.isTourPaused else { return }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self.executeStepAt(index: 0)
                }
            }
        } else {
            executeStepAt(index: 0)
        }
    }

    public func nextTourStep() {
        guard AppState.shared.isTourActive, !tourSteps.isEmpty else { return }
        AudioManager.shared.stopAudio(notifyCompletion: false)
        if tourCurrentIndex + 1 < tourSteps.count {
            tourCurrentIndex += 1
            executeStepAt(index: tourCurrentIndex)
        } else {
            finishTour()
        }
    }

    public func prevTourStep() {
        guard AppState.shared.isTourActive, !tourSteps.isEmpty else { return }
        AudioManager.shared.stopAudio(notifyCompletion: false)
        if tourCurrentIndex > 0 {
            tourCurrentIndex -= 1
            executeStepAt(index: tourCurrentIndex)
        }
    }

    public func toggleTourPause() {
        guard AppState.shared.isTourActive else { return }
        AppState.shared.isTourPaused.toggle()
        if AppState.shared.isTourPaused {
            AudioManager.shared.stopAudio(notifyCompletion: false)
            AppState.shared.statusMessage = "Tour paused"
        } else {
            executeStepAt(index: tourCurrentIndex)
        }
    }

    private func executeStepAt(index: Int) {
        guard index >= 0 && index < tourSteps.count else { return }
        tourCurrentIndex = index
        let step = tourSteps[index]
        let stepNum = index + 1
        AppState.shared.currentTourStep = stepNum
        AppState.shared.statusMessage = "Tour: \(step.label) (\(stepNum)/\(tourSteps.count))"

        let screenX = tourScreenFrame.origin.x + (step.pointNormalized.x / 1000.0) * tourScreenFrame.width
        let screenY = tourScreenFrame.origin.y + (step.pointNormalized.y / 1000.0) * tourScreenFrame.height

        AppState.shared.targetPoint = CGPoint(x: screenX, y: screenY)
        AppState.shared.targetLabel = step.label
        AppState.shared.companionState = .pointing
        AppState.shared.lastAIResponse = "\(step.label): \(step.narration)"

        speak(step.narration) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, AppState.shared.isTourActive, !AppState.shared.isTourPaused else { return }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard AppState.shared.isTourActive, !AppState.shared.isTourPaused, self.tourCurrentIndex == index else { return }
                self.nextTourStep()
            }
        }
    }

    private func finishTour() {
        AppState.shared.companionState = .happy
        AppState.shared.targetPoint = nil
        AppState.shared.targetLabel = nil
        AppState.shared.statusMessage = "Tour complete!"
        let wrapUp = "And that wraps up the tour! Let me know what you'd like to do next."
        AppState.shared.lastAIResponse = wrapUp
        speak(wrapUp)

        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard AppState.shared.companionState == .happy else { return }
            AppState.shared.isTourActive = false
            AppState.shared.currentTourStep = 0
            AppState.shared.totalTourSteps = 0
            AppState.shared.activeTourSteps = []
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "Ready"
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            AppState.shared.lastAIResponse = ""
        }
    }

    public func cancelTour() {
        guard AppState.shared.isTourActive else { return }
        AudioManager.shared.stopAudio(notifyCompletion: false)
        AppState.shared.isTourActive = false
        AppState.shared.isTourPaused = false
        AppState.shared.currentTourStep = 0
        AppState.shared.totalTourSteps = 0
        AppState.shared.activeTourSteps = []
        AppState.shared.targetPoint = nil
        AppState.shared.targetLabel = nil
        AppState.shared.companionState = .idle
        AppState.shared.statusMessage = "Ready"
        AppState.shared.lastAIResponse = ""
    }

    private func synthesizeFallbackTour(forApp: String) -> [TourStep] {
        let lower = forApp.lowercased()

        if lower.contains("vn") || lower.contains("premiere") || lower.contains("final cut") || lower.contains("davinci") || lower.contains("imovie") || lower.contains("video") {
            return [
                TourStep(
                    pointNormalized: CGPoint(x: 500, y: 55),
                    label: "Toolbar & Export",
                    narration: "At the top is the main toolbar and the export button where you render your finished project at full resolution."
                ),
                TourStep(
                    pointNormalized: CGPoint(x: 180, y: 250),
                    label: "Media Library & Assets",
                    narration: "Here on the left is your media pool where you import footage, audio effects, titles, and stickers."
                ),
                TourStep(
                    pointNormalized: CGPoint(x: 520, y: 360),
                    label: "Video Preview Monitor",
                    narration: "In the center is your live playback screen where you review your edits, aspect ratios, and visual effects."
                ),
                TourStep(
                    pointNormalized: CGPoint(x: 500, y: 720),
                    label: "Multi-Track Timeline",
                    narration: "Down here is the editing timeline where you can scrub footage horizontally, reorder clips, and synchronize audio."
                ),
                TourStep(
                    pointNormalized: CGPoint(x: 320, y: 840),
                    label: "Speed & Editing Tools",
                    narration: "Along the bottom toolbar are your precision editing actions like Split, Speed curves to slow down or speed up clips, and Transitions."
                )
            ]
        }

        if lower.contains("antigravity") || lower.contains("xcode") || lower.contains("code") || lower.contains("cursor") || lower.contains("terminal") {
            return [
                TourStep(
                    pointNormalized: CGPoint(x: 500, y: 50),
                    label: "Command Palette & Tabs",
                    narration: "At the top is the header navigation, open file tabs, and the command palette for instant commands."
                ),
                TourStep(
                    pointNormalized: CGPoint(x: 160, y: 350),
                    label: "Project Explorer & AI Assistant",
                    narration: "On the left sidebar you can browse your workspace files, git commits, and your AI assistant panel."
                ),
                TourStep(
                    pointNormalized: CGPoint(x: 550, y: 450),
                    label: "Central Code Editor",
                    narration: "In the center is your main editor window with syntax highlighting, inline diagnostics, and code definitions."
                ),
                TourStep(
                    pointNormalized: CGPoint(x: 500, y: 850),
                    label: "Terminal & Diagnostics",
                    narration: "At the bottom is the integrated terminal, debug console, and build outputs for running your code."
                )
            ]
        }

        return [
            TourStep(
                pointNormalized: CGPoint(x: 500, y: 55),
                label: "Top Controls & Navigation",
                narration: "Here at the top is the primary navigation header and toolbar for \(forApp), where you access core view options and commands."
            ),
            TourStep(
                pointNormalized: CGPoint(x: 180, y: 350),
                label: "Left Navigation Sidebar",
                narration: "On the left side is your explorer sidebar, letting you navigate project files, channels, or document hierarchies."
            ),
            TourStep(
                pointNormalized: CGPoint(x: 560, y: 480),
                label: "Central Active Workspace",
                narration: "In the center is your main active workspace and canvas, where you read, edit, and create your work."
            ),
            TourStep(
                pointNormalized: CGPoint(x: 500, y: 880),
                label: "Bottom Utility & Status Bar",
                narration: "At the bottom is the utility bar and status panel, showing live state, terminal diagnostics, and notifications."
            )
        ]
    }

    private func isBackgroundTaskRequest(_ prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return lower.contains("in the background") ||
               lower.contains("create a task") ||
               lower.contains("spawn agent") ||
               lower.contains("summarize in background") ||
               lower.contains("write a document")
    }
}
