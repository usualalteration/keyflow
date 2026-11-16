import Foundation
import AVFoundation

/// Taps the main mixer output, i.e. the *actual* post-volume audio that reaches the speakers,
/// and derives waveform, FFT bands and levels from it. The tap runs on a CoreAudio worker thread,
/// never on the synthesizer's render thread.
final class AudioAnalyzer {
    struct Snapshot {
        var waveform: [Float] = []
        var bands: [Float] = []
        var bass: Float = 0
        var mid: Float = 0
        var treble: Float = 0
        var rms: Float = 0
        var peak: Float = 0
    }

    static let ringSize = 8192
    static let fftSize = 2048
    static let bandCount = 48

    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: AudioAnalyzer.ringSize)
    private var writeIndex = 0
    private var scratch = [Float](repeating: 0, count: 4096)
    private var fftInput = [Float](repeating: 0, count: AudioAnalyzer.fftSize)
    private let fft = FFTProcessor(size: AudioAnalyzer.fftSize)
    private var bands = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
    private var bass: Float = 0, mid: Float = 0, treble: Float = 0
    private var rms: Float = 0, peak: Float = 0
    private var sampleRate: Double = 48000
    private var installedOn: AVAudioNode?
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    /// 0...1, set from the UI preference.
    var smoothing: Float = 0.6

    func setSink(_ s: ((AVAudioPCMBuffer) -> Void)?) {
        lock.lock(); sink = s; lock.unlock()
    }

    func install(on node: AVAudioNode, sampleRate: Double) {
        self.sampleRate = sampleRate
        installedOn = node
        node.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            self?.process(buffer)
        }
    }

    func remove() {
        installedOn?.removeTap(onBus: 0)
        installedOn = nil
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let forward = sink
        lock.unlock()
        forward?(buffer)

        guard let ch = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        let chans = Int(buffer.format.channelCount)
        if n == 0 || chans == 0 { return }
        if scratch.count < n { scratch = [Float](repeating: 0, count: n) }

        var sumSq: Float = 0
        var pk: Float = 0
        for i in 0..<n {
            var v: Float = 0
            for c in 0..<chans { v += ch[c][i] }
            v /= Float(chans)
            scratch[i] = v
            sumSq += v * v
            pk = max(pk, abs(v))
        }

        lock.lock()
        for i in 0..<n {
            ring[writeIndex] = scratch[i]
            writeIndex += 1
            if writeIndex == AudioAnalyzer.ringSize { writeIndex = 0 }
        }
        rms = rms * 0.6 + 0.4 * sqrtf(sumSq / Float(n))
        peak = max(pk, peak * 0.93)
        var start = writeIndex - AudioAnalyzer.fftSize
        if start < 0 { start += AudioAnalyzer.ringSize }
        for i in 0..<AudioAnalyzer.fftSize {
            fftInput[i] = ring[(start + i) % AudioAnalyzer.ringSize]
        }
        lock.unlock()

        fftInput.withUnsafeBufferPointer { fft.process($0.baseAddress!) }
        let mags = fft.magnitudes
        let nb = AudioAnalyzer.bandCount
        let binHz = Float(sampleRate) / Float(AudioAnalyzer.fftSize)
        let decay = 0.78 + 0.19 * smoothing
        var newBands = [Float](repeating: 0, count: nb)
        let fLo: Float = 30, fHi: Float = min(16000, Float(sampleRate) * 0.45)
        for b in 0..<nb {
            let f0 = fLo * powf(fHi / fLo, Float(b) / Float(nb))
            let f1 = fLo * powf(fHi / fLo, Float(b + 1) / Float(nb))
            let b0 = max(1, Int(f0 / binHz))
            let b1 = min(mags.count - 1, max(b0, Int(f1 / binHz)))
            var m: Float = 0
            for k in b0...b1 { m = max(m, mags[k]) }
            let fc = sqrtf(f0 * f1)
            let tilt = max(0, 4.5 * log2f(fc / 100))      // compensate the natural spectral roll-off
            let db = 20 * log10f(max(m, 1e-9)) + tilt
            newBands[b] = min(1, max(0, (db + 88) / 70))
        }

        lock.lock()
        for b in 0..<nb {
            bands[b] = newBands[b] > bands[b] ? newBands[b] : bands[b] * decay + newBands[b] * (1 - decay)
        }
        func avg(_ r: Range<Int>) -> Float { r.map { bands[$0] }.reduce(0, +) / Float(r.count) }
        bass = avg(0..<10); mid = avg(10..<32); treble = avg(32..<nb)
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        var s = Snapshot()
        let n = AudioAnalyzer.fftSize
        var w = [Float](repeating: 0, count: n)
        var start = writeIndex - n
        if start < 0 { start += AudioAnalyzer.ringSize }
        for i in 0..<n { w[i] = ring[(start + i) % AudioAnalyzer.ringSize] }
        s.waveform = w
        s.bands = bands
        s.bass = bass; s.mid = mid; s.treble = treble
        s.rms = rms; s.peak = peak
        return s
    }
}
