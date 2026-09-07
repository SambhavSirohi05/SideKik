import Foundation
import AppKit
import CoreGraphics

/// Central state machine orchestrating audio capture, screen grabs, AI inference, and overlay animations
@MainActor
public final class CompanionOrchestrator: ObservableObject {
    public static let shared = CompanionOrchestrator()

    private var isProcessing = false

    private init() {}

    /// Triggered when the push-to-talk hotkey is pressed down
    public func startPushToTalk() {
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

    /// Executes end-to-end multi-modal flow
    public func processInteraction(audioData: Data?, typedPrompt: String? = nil) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // 1. Privacy Guard Check
        let privacyCheck = PrivacyGuard.shared.validateScreenCapture()
        guard privacyCheck.isAllowed else {
            AppState.shared.companionState = .alert
            AppState.shared.statusMessage = "Screen masked: \(privacyCheck.reason ?? "Privacy")"
            speakResponse("I cannot inspect the screen right now because a protected window is active.")
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

        if userQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "No speech detected"
            return
        }

        AppState.shared.lastSpokenTranscript = userQuestion

        // Check if user is asking for a background task (e.g. "summarize this in background", "create a file", etc.)
        if isBackgroundTaskRequest(userQuestion) {
            WorkerManager.shared.spawnTask(title: "Autonomous Agent Task", brief: userQuestion)
            return
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
            speakResponse("I couldn't capture the screen. Please verify Screen Recording permissions in System Settings.")
            return
        }

        // 4. Multimodal Vision Reasoning (Google Gemini 2.0 Flash)
        let geminiKey = AppState.shared.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var aiResponse: AIResponse? = nil

        if !geminiKey.isEmpty {
            do {
                aiResponse = try await GeminiClient.shared.analyzeScreen(
                    question: userQuestion,
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
            // No API key yet: provide friendly guidance
            aiResponse = AIResponse(
                spokenText: "I see \(activeApp) on your screen! Please add your free Google AI Studio API key in the menu bar to enable full visual reasoning.",
                rawText: "Please add your API key in Settings."
            )
        }

        guard let result = aiResponse else {
            AppState.shared.companionState = .error
            return
        }

        AppState.shared.lastAIResponse = result.spokenText

        // 5. Calculate Cocoa Coordinates from Normalized Vision Points
        var targetCocoaX: Double = 0
        var targetCocoaY: Double = 0

        if let norm = result.targetPointNormalized {
            let screenFrame = capture.screenFrame
            // Vision origin: Top-Left (0,0) -> Bottom-Right (1000, 1000)
            // Cocoa origin: Bottom-Left (origin.x, origin.y) -> Top-Right
            let cocoaX = screenFrame.origin.x + (norm.x / 1000.0) * screenFrame.width
            let cocoaY = screenFrame.origin.y + screenFrame.height - (norm.y / 1000.0) * screenFrame.height

            targetCocoaX = cocoaX
            targetCocoaY = cocoaY

            AppState.shared.targetPoint = CGPoint(x: cocoaX, y: cocoaY)
            AppState.shared.targetLabel = result.targetLabel ?? "Target"
            AppState.shared.companionState = .pointing
        } else {
            AppState.shared.targetPoint = nil
            AppState.shared.targetLabel = nil
            AppState.shared.companionState = .speaking
        }

        // 6. Log to Local SQLite Journal
        JournalDatabase.shared.insertEntry(
            appName: activeApp,
            question: userQuestion,
            answer: result.spokenText,
            targetX: targetCocoaX,
            targetY: targetCocoaY
        )

        // 7. Text-to-Speech Synthesis
        speakResponse(result.spokenText)
    }

    private func speakResponse(_ text: String) {
        AppState.shared.companionState = (AppState.shared.targetPoint != nil ? .pointing : .speaking)
        AppState.shared.statusMessage = "Speaking..."

        let sarvamKey = AppState.shared.sarvamApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !sarvamKey.isEmpty && !AppState.shared.useLocalSpeechFallback {
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
                        }
                    }
                } catch {
                    print("Sarvam TTS failed, falling back to macOS native voice: \(error)")
                    speakNative(text)
                }
            }
        } else {
            speakNative(text)
        }
    }

    private func speakNative(_ text: String) {
        NativeSpeechFallback.shared.speak(text: text) { [weak self] in
            Task { @MainActor in
                self?.finishSpeaking()
            }
        }
    }

    private func finishSpeaking() {
        Task { @MainActor in
            // Hold position for 1.5 seconds then return to resting state
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            AppState.shared.targetPoint = nil
            AppState.shared.targetLabel = nil
            AppState.shared.companionState = .idle
            AppState.shared.statusMessage = "Ready"
        }
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
