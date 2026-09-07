import Foundation
import AVFoundation

/// Manages microphone audio capture and synthesized audio playback with hardware resilience
public final class AudioManager: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    public static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private var pcmBufferData = Data()
    private var isRecording = false
    private let recordingLock = NSLock()
    private var player: AVAudioPlayer?
    private var onPlaybackFinished: (@Sendable () -> Void)?

    private var activeSampleRate: Double = 16000.0
    private var activeChannelCount: Int = 1

    private override init() {
        super.init()
    }

    /// Starts capturing microphone audio into in-memory buffer
    public func startRecording() throws {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        guard !isRecording else { return }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        self.activeSampleRate = hardwareFormat.sampleRate
        self.activeChannelCount = Int(hardwareFormat.channelCount)

        pcmBufferData.removeAll(keepingCapacity: true)

        // Install buffer tap using native hardware format to avoid format mismatch crashes
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.appendAudioBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops audio capture and returns a standard RIFF WAV payload
    public func stopRecording() -> Data? {
        recordingLock.lock()
        defer { recordingLock.unlock() }

        guard isRecording else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        guard !pcmBufferData.isEmpty else { return nil }

        // Wrap accumulated PCM data into standard 44-byte WAV header
        return createWAVFile(from: pcmBufferData, sampleRate: Int(activeSampleRate), channels: 1, bitsPerSample: 16)
    }

    private func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)

        var monoPCM16 = [Int16](repeating: 0, count: frameLength)

        // Downmix to mono and convert Float32 [-1.0, 1.0] to Int16
        for frame in 0..<frameLength {
            var sampleSum: Float = 0.0
            for channel in 0..<channels {
                sampleSum += channelData[channel][frame]
            }
            let avgSample = max(-1.0, min(1.0, sampleSum / Float(channels)))
            monoPCM16[frame] = Int16(avgSample * 32767.0)
        }

        monoPCM16.withUnsafeBytes { rawBufferPointer in
            recordingLock.lock()
            pcmBufferData.append(contentsOf: rawBufferPointer)
            recordingLock.unlock()
        }
    }

    /// Generates RIFF/WAVE header and appends linear PCM samples
    private func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var header = Data()

        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let totalDataLen = pcmData.count
        let totalAudioLen = totalDataLen + 36

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(UInt32(totalAudioLen).littleEndianData)
        header.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(UInt32(16).littleEndianData) // Subchunk1Size (16 for PCM)
        header.append(UInt16(1).littleEndianData)  // AudioFormat (1 = PCM)
        header.append(UInt16(channels).littleEndianData)
        header.append(UInt32(sampleRate).littleEndianData)
        header.append(UInt32(byteRate).littleEndianData)
        header.append(UInt16(blockAlign).littleEndianData)
        header.append(UInt16(bitsPerSample).littleEndianData)

        // data subchunk
        header.append(contentsOf: "data".utf8)
        header.append(UInt32(totalDataLen).littleEndianData)

        return header + pcmData
    }

    /// Plays audio data (e.g. decoded WAV/MP3 from Sarvam Bulbul v3)
    public func playAudio(data: Data, completion: (@Sendable () -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            do {
                self.onPlaybackFinished = completion
                self.player = try AVAudioPlayer(data: data)
                self.player?.delegate = self
                self.player?.prepareToPlay()
                self.player?.play()
            } catch {
                print("Failed to initialize audio player: \(error)")
                completion?()
            }
        }
    }

    public var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    public func stopAudio(notifyCompletion: Bool = false) {
        let callback = onPlaybackFinished
        onPlaybackFinished = nil
        player?.stop()
        player = nil
        if notifyCompletion {
            callback?()
        }
    }

    // MARK: - AVAudioPlayerDelegate
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let callback = onPlaybackFinished
        onPlaybackFinished = nil
        callback?()
    }
}

// MARK: - Helper extensions for little-endian integer byte serialization
private extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}
