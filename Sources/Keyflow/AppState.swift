import Foundation
import Combine
import AppKit

/// Wires the modules together. Main-thread only; the audio thread talks to it exclusively through `SharedParams`.
final class AppState: ObservableObject {
    let settings = SettingsManager()
    let presets = PresetManager()
    let audio = AudioEngine()
    let recorder = RecordingManager()
    let keyboard = KeyboardMonitor()
    let rhythm = TypingRhythmAnalyzer()
    let mapping = MusicalMappingEngine()

    @Published private(set) var monitoringActive = false
    @Published private(set) var inputAccessGranted = false

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastGenre: Genre?
    private var lastMonitoring: Bool?
    private var lastDevice: String?
    private var tickCount = 0
    private var started = false

    init() {
        let rhythm = self.rhythm
        let shared = audio.shared
        keyboard.onKeyDown = { t in
            rhythm.registerDown(at: t)
            shared.mutate { $0.keyHits &+= 1 }
        }
        keyboard.onKeyUp = { _ in rhythm.registerUp() }
    }

    func start() {
        guard !started else { return }
        started = true
        audio.outputUID = settings.config.outputDeviceUID
        lastDevice = settings.config.outputDeviceUID
        audio.setVolume(Float(settings.config.volume))
        audio.start()
        applyMonitoring(settings.config.monitoring)

        settings.$config
            .removeDuplicates()
            .sink { [weak self] cfg in self?.configChanged(cfg) }
            .store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func configChanged(_ cfg: Configuration) {
        if lastMonitoring != cfg.monitoring { applyMonitoring(cfg.monitoring) }
        if lastDevice != cfg.outputDeviceUID {
            lastDevice = cfg.outputDeviceUID
            audio.setOutputDevice(uid: cfg.outputDeviceUID)
        }
        audio.setVolume(Float(cfg.volume))
        audio.analyzer.smoothing = Float(cfg.vizSmoothing)
        audio.setEQ(gains: cfg.eqGains.map { Float($0) }, enabled: cfg.eqEnabled)
    }

    func applyMonitoring(_ on: Bool) {
        lastMonitoring = on
        if on {
            monitoringActive = keyboard.start()
        } else {
            keyboard.stop()
            monitoringActive = false
        }
        inputAccessGranted = keyboard.hasAccess
    }

    func openInputMonitoringSettings() {
        keyboard.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func tick() {
        tickCount += 1
        let cfg = settings.config
        let profile = GenreProfile.profile(cfg.genre)
        if lastGenre != cfg.genre {
            lastGenre = cfg.genre
            audio.shared.setProfile(profile)
        }

        // Retry the tap once permission appears (checked once per second).
        if tickCount % 30 == 0 {
            let granted = keyboard.hasAccess
            if granted != inputAccessGranted { inputAccessGranted = granted }
            if cfg.monitoring && granted && !keyboard.isActive { monitoringActive = keyboard.start() }
        }

        let snap = rhythm.snapshot(now: ProcessInfo.processInfo.systemUptime)
        let ctl = mapping.update(dt: 1.0 / 30.0, typing: snap, config: cfg, profile: profile)
        let scaleIndex = ScaleType.allCases.firstIndex(of: cfg.scale) ?? 0
        audio.shared.mutate { p in
            p.bpm = cfg.bpm
            p.keyRoot = cfg.keyRoot
            p.scaleIndex = scaleIndex
            p.energy = ctl.energy
            p.complexity = ctl.complexity
            p.atmosphere = ctl.atmosphere
            p.swing = ctl.swing
            p.humanize = ctl.humanize
            p.density = Float(cfg.density)
            p.seed = cfg.seed
            p.layerMask = cfg.layerMask
            if ctl.fillRequest { p.fillCounter &+= 1 }
            if ctl.riserRequest { p.riserCounter &+= 1 }
        }
    }

    /// Asks for confirmation, then runs the uninstaller (embedded in the app, so it never depends on
    /// a bundled file) detached from this process, and quits.
    func confirmUninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall KEYFLOW?"
        alert.informativeText = "This removes the app, its preferences and its Input Monitoring permission. WAV files you exported are not touched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else {
            let info = NSAlert()
            info.messageText = "Uninstall is only available in the installed app."
            info.informativeText = "Run scripts/uninstall.sh from Terminal instead."
            info.runModal()
            return
        }
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("keyflow-uninstall.sh")
        do {
            try uninstallScriptSource.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            let fail = NSAlert()
            fail.messageText = "Could not start the uninstaller."
            fail.informativeText = "Run scripts/uninstall.sh from Terminal, or drag KEYFLOW to the Trash."
            fail.runModal()
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "nohup /bin/bash \"$0\" --yes --app \"$1\" >/dev/null 2>&1 &", scriptURL.path, bundlePath]
        do { try p.run() } catch { return }
        keyboard.stop()
        recorder.stop(analyzer: audio.analyzer)
        NSApp.terminate(nil)
    }

    func togglePlay() { audio.isPlaying.toggle() }

    func toggleRecording() {
        if recorder.isRecording { recorder.stop(analyzer: audio.analyzer) }
        else { recorder.start(analyzer: audio.analyzer) }
    }
}
