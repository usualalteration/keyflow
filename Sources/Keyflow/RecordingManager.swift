import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// Records exactly what the analyzer tap hears (the final mix) to a 24-bit WAV file.
final class RecordingManager: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastRecording: URL?

    private let queue = DispatchQueue(label: "keyflow.recording")
    private var file: AVAudioFile?
    private var url: URL?
    private var timer: Timer?
    private var startedAt = Date()

    func start(analyzer: AudioAnalyzer) {
        guard !isRecording else { return }
        let name = "KEYFLOW-\(Int(Date().timeIntervalSince1970)).wav"
        url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        file = nil
        analyzer.setSink { [weak self] buffer in self?.append(buffer) }
        isRecording = true
        elapsed = 0
        startedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsed = Date().timeIntervalSince(self.startedAt)
        }
    }

    func stop(analyzer: AudioAnalyzer) {
        guard isRecording else { return }
        analyzer.setSink(nil)
        timer?.invalidate(); timer = nil
        isRecording = false
        queue.sync { self.file = nil }     // closes and finalizes the WAV header
        lastRecording = url
    }

    /// Called on the analyzer's tap thread; the file write happens on our own queue.
    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let src = buffer.floatChannelData, let dst = copy.floatChannelData else { return }
        copy.frameLength = buffer.frameLength
        for c in 0..<Int(buffer.format.channelCount) {
            memcpy(dst[c], src[c], Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }
        queue.async { [weak self] in
            guard let self = self, let url = self.url else { return }
            if self.file == nil {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: copy.format.sampleRate,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 24,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                self.file = try? AVAudioFile(forWriting: url, settings: settings,
                                             commonFormat: .pcmFormatFloat32, interleaved: false)
            }
            try? self.file?.write(from: copy)
        }
    }

    func exportLast() {
        guard let src = lastRecording else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.wav]
        panel.nameFieldStringValue = src.lastPathComponent
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: src, to: dest)
        }
    }
}
