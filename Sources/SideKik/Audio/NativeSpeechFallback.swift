import Foundation
import AVFoundation

/// Zero-cost, 100% offline speech synthesis using macOS native AVSpeechSynthesizer
public final class NativeSpeechFallback: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = NativeSpeechFallback()

    private let synthesizer = AVSpeechSynthesizer()
    private var onSpeechFinished: (@Sendable () -> Void)?
    private let lock = NSLock()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks text using the best available native macOS voice
    public func speak(text: String, rate: Float = 0.52, completion: (@Sendable () -> Void)? = nil) {
        lock.lock()
        self.onSpeechFinished = completion
        lock.unlock()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0

        // Prefer enhanced or Siri English voice if available, fallback to en-US/en-GB/en-IN
        if let preferredVoice = AVSpeechSynthesisVoice(language: "en-IN") ??
            AVSpeechSynthesisVoice(language: "en-US") ??
            AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.starts(with: "en") }) {
            utterance.voice = preferredVoice
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }
            self.synthesizer.speak(utterance)
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lock.lock()
        let callback = onSpeechFinished
        onSpeechFinished = nil
        lock.unlock()
        callback?()
    }

    // MARK: - AVSpeechSynthesizerDelegate
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        lock.lock()
        let callback = onSpeechFinished
        onSpeechFinished = nil
        lock.unlock()
        callback?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        lock.lock()
        let callback = onSpeechFinished
        onSpeechFinished = nil
        lock.unlock()
        callback?()
    }
}
