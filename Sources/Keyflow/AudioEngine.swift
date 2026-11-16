import Foundation
import AVFoundation
import AudioToolbox

final class AudioEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var isPlaying = true {
        didSet { shared.mutate { $0.playing = self.isPlaying } }
    }
    @Published private(set) var status = "Stopped"
    @Published private(set) var sampleRate: Double = 0
    @Published private(set) var deviceName = "—"

    let shared = SharedParams()
    let analyzer = AudioAnalyzer()

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 10)
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0))
    private var eqGains = [Float](repeating: 0, count: 10)
    private var eqOn = true
    static let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private var core: SynthCore?
    private var node: AVAudioSourceNode?
    private var volume: Float = 0.6
    var outputUID = ""
    private var configObserver: NSObjectProtocol?

    init() {
        for (i, f) in AudioEngine.eqFrequencies.enumerated() {
            let b = eq.bands[i]
            b.filterType = i == 0 ? .lowShelf : (i == 9 ? .highShelf : .parametric)
            b.frequency = f
            b.bandwidth = 1.0
            b.gain = 0
            b.bypass = false
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.stop()
            self.start()
        }
    }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    }

    func setVolume(_ v: Float) {
        volume = v
        engine.mainMixerNode.outputVolume = v
    }

    func start() {
        guard !isRunning else { return }
        applyOutputDevice()
        let out = engine.outputNode.outputFormat(forBus: 0)
        let sr = out.sampleRate > 0 ? out.sampleRate : 48000
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else {
            status = "Format error"; return
        }
        let core = SynthCore(sampleRate: Float(sr), shared: shared)
        self.core = core
        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            if list.count >= 2, let l = list[0].mData, let r = list[1].mData {
                core.render(frames: Int(frameCount),
                            left: l.assumingMemoryBound(to: Float.self),
                            right: r.assumingMemoryBound(to: Float.self))
            }
            return noErr
        }
        self.node = node
        engine.attach(node)
        engine.attach(eq)
        engine.attach(limiter)
        engine.connect(node, to: eq, format: fmt)
        engine.connect(eq, to: limiter, format: fmt)
        engine.connect(limiter, to: engine.mainMixerNode, format: fmt)
        applyEQ()
        engine.mainMixerNode.outputVolume = volume
        analyzer.install(on: engine.mainMixerNode, sampleRate: sr)
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            sampleRate = sr
            status = "Running"
            deviceName = outputUID.isEmpty ? AudioDevices.defaultOutputName()
                : (AudioDevices.outputDevices().first { $0.uid == outputUID }?.name ?? "Selected device")
        } catch {
            status = "Error: \(error.localizedDescription)"
            analyzer.remove()
            engine.detach(node)
            engine.detach(eq)
            engine.detach(limiter)
            self.node = nil
        }
    }

    func stop() {
        guard isRunning else { return }
        analyzer.remove()
        engine.stop()
        if let n = node { engine.detach(n) }
        engine.detach(eq)
        engine.detach(limiter)
        node = nil
        core = nil
        isRunning = false
        status = "Stopped"
    }

    /// 10-band equalizer applied to the synth before the output (and before the visualizers).
    func setEQ(gains: [Float], enabled: Bool) {
        guard gains.count == 10 else { return }
        eqGains = gains
        eqOn = enabled
        applyEQ()
    }

    private func applyEQ() {
        for i in 0..<10 { eq.bands[i].gain = eqOn ? eqGains[i] : 0 }
        // Pull the overall level down a little when boosting, so EQ boosts don't push the mix into the limiter.
        let boost = eqOn ? max(0, eqGains.max() ?? 0) : 0
        eq.globalGain = -boost * 0.6
    }

    func setOutputDevice(uid: String) {
        outputUID = uid
        if isRunning { stop(); start() }
    }

    private func applyOutputDevice() {
        guard !outputUID.isEmpty,
              let dev = AudioDevices.outputDevices().first(where: { $0.uid == outputUID }),
              let unit = engine.outputNode.audioUnit else { return }
        var id = dev.id
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    func meters() -> SynthMeters { core?.meters() ?? SynthMeters() }
}
