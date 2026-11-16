import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        VStack(spacing: 14) {
            HeaderView()
            VisualizationPanel()
                .frame(minHeight: 230)
            ControlsPanel()
            BottomPanel()
        }
        .padding(18)
        .background(Theme.bg)
        .frame(minWidth: 780, minHeight: 660)
        .id(settings.config.accent)   // rebuild the whole UI when the neon palette changes
    }
}

// MARK: Header

struct HeaderView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var audio: AudioEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            (Text("KEY").foregroundColor(.white) + Text("FLOW").foregroundColor(Theme.accent))
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .kerning(4)
                .shadow(color: Theme.accent.opacity(0.5), radius: 8)
                .padding(.leading, 64)   // room for the traffic-light buttons
            Spacer()
            StatusPill(label: audio.isRunning ? "ENGINE · \(audio.status.uppercased())" : "ENGINE · OFF",
                       color: audio.isRunning ? Theme.accent : .red)
            Button {
                settings.config.monitoring.toggle()
            } label: {
                StatusPill(label: keysLabel, color: keysColor)
            }
            .buttonStyle(.plain)
            .help("Toggle global keyboard monitoring (timing only — never content)")
            Menu {
                ForEach(AccentColor.allCases) { a in
                    Button(a.rawValue) { settings.config.accent = a }
                }
            } label: {
                Circle().fill(Theme.accent).frame(width: 14, height: 14)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 4)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Neon color")
            Button { openWindow(id: "settings") } label: {
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundColor(Theme.dim)
            }
            .buttonStyle(.plain)
        }
    }

    private var keysLabel: String {
        if !settings.config.monitoring { return "KEYS · OFF" }
        if app.monitoringActive { return "KEYS · LISTENING" }
        return "KEYS · NEEDS PERMISSION"
    }
    private var keysColor: Color {
        if !settings.config.monitoring { return Theme.dim }
        return app.monitoringActive ? Theme.cyan : .orange
    }
}

struct StatusPill: View {
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 4)
            Text(label).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Theme.line))
    }
}

// MARK: Visualization

struct VisualizationPanel: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var audio: AudioEngine

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Theme.panel)
            Group {
                switch settings.config.visualization {
                case .waveform: WaveformVisualizer(analyzer: audio.analyzer)
                case .spectrum: SpectrumVisualizer(analyzer: audio.analyzer).padding(14)
                case .pulse:
                    PulseVisualizer(analyzer: audio.analyzer,
                                    meters: { audio.meters() },
                                    particlesEnabled: settings.config.showParticles)
                case .equalizer:
                    EqualizerView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .overlay(alignment: .topLeading) { modePicker.padding(12) }
        .overlay(alignment: .topTrailing) {
            if settings.config.visualization != .equalizer { LevelReadout().padding(16) }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(VisualizationMode.allCases) { m in
                Button { settings.config.visualization = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .foregroundColor(settings.config.visualization == m ? .black : Theme.dim)
                        .background(Capsule().fill(settings.config.visualization == m ? Theme.accent : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().stroke(Theme.line))
    }
}

struct LevelReadout: View {
    @EnvironmentObject var audio: AudioEngine
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let s = audio.analyzer.snapshot()
            let db = s.peak > 0.00001 ? 20 * log10(Double(s.peak)) : -99
            Text(String(format: "OUT %@ dBFS", db <= -90 ? "−∞" : String(format: "%.1f", db)))
                .font(Theme.mono).foregroundColor(db > -1 ? .red : Theme.dim)
        }
    }
}

// MARK: Controls

struct ControlCell<Content: View>: View {
    let title: String
    let value: String
    let content: Content
    init(_ title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.value = value; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.dim).kerning(1.5)
                Spacer()
                Text(value).font(Theme.mono).foregroundColor(Theme.accent)
            }
            content
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}

struct ControlsPanel: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var audio: AudioEngine
    @EnvironmentObject var recorder: RecordingManager

    var body: some View {
        let profile = GenreProfile.profile(settings.config.genre)
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { app.togglePlay() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        Text(audio.isPlaying ? "PAUSE" : "PLAY")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accent))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [.command])

                Button { app.toggleRecording() } label: {
                    HStack(spacing: 6) {
                        Circle().fill(recorder.isRecording ? Color.red : Theme.dim).frame(width: 8, height: 8)
                        Text(recorder.isRecording ? "REC \(timeString(recorder.elapsed))" : "REC")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.panel))
                    .overlay(Capsule().stroke(Theme.line))
                }
                .buttonStyle(.plain)

                if recorder.lastRecording != nil && !recorder.isRecording {
                    Button("EXPORT WAV…") { recorder.exportLast() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                }
                Spacer()
                Text("SEED \(settings.config.seed)").font(Theme.mono).foregroundColor(Theme.dim)
                Button { settings.randomizeSeed() } label: {
                    Image(systemName: "dice").foregroundColor(Theme.dim)
                }
                .buttonStyle(.plain).help("New random seed")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ControlCell("GENRE", value: "") {
                    Picker("", selection: Binding(get: { settings.config.genre },
                                                  set: { settings.selectGenre($0) })) {
                        ForEach(Genre.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
                ControlCell("BPM", value: String(format: "%.0f", settings.config.bpm)) {
                    Slider(value: $settings.config.bpm, in: profile.bpmRange, step: 1).tint(Theme.accent)
                }
                ControlCell("KEY / SCALE", value: "\(NoteNames.all[settings.config.keyRoot]) \(settings.config.scale.rawValue)") {
                    HStack {
                        Picker("", selection: $settings.config.keyRoot) {
                            ForEach(0..<12, id: \.self) { Text(NoteNames.all[$0]).tag($0) }
                        }
                        .pickerStyle(.menu).labelsHidden().frame(width: 70)
                        Picker("", selection: $settings.config.scale) {
                            ForEach(ScaleType.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }
                }
                ControlCell("INTENSITY", value: String(format: "%.0f%%", settings.config.intensity * 100)) {
                    Slider(value: $settings.config.intensity, in: 0...1).tint(Theme.accent)
                }
                ControlCell("VOLUME", value: String(format: "%.0f%%", settings.config.volume * 100)) {
                    Slider(value: $settings.config.volume, in: 0...1).tint(Theme.cyan)
                }
                ControlCell("TYPING SENSITIVITY", value: String(format: "×%.2f", settings.config.sensitivity)) {
                    Slider(value: $settings.config.sensitivity, in: 0.25...2.5).tint(Theme.accent)
                }
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: Bottom

struct BottomPanel: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var audio: AudioEngine

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { _ in
            let m = audio.meters()
            let t = app.rhythm.snapshot(now: ProcessInfo.processInfo.systemUptime)
            HStack(spacing: 16) {
                ActivityMeter(name: "DRUMS", value: m.drums)
                ActivityMeter(name: "BASS", value: m.bass)
                ActivityMeter(name: "MELODY", value: m.melody)
                Divider().frame(height: 24).overlay(Theme.line)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TYPING  \(String(format: "%.1f", t.shortKPS)) keys/s · \(t.idleSeconds > 900 ? "idle" : String(format: "idle %.0fs", t.idleSeconds))")
                    Text("OUTPUT  \(audio.deviceName) · \(audio.sampleRate > 0 ? String(format: "%.1f kHz", audio.sampleRate / 1000) : "—") · \(audio.isRunning ? (audio.isPlaying ? "live" : "paused") : "stopped")")
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(Theme.dim)
                .lineLimit(1)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        }
    }
}

struct ActivityMeter: View {
    let name: String
    let value: Float
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.dim).kerning(1.2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(min(1, value * 1.6)))
                }
            }
            .frame(width: 90, height: 5)
        }
    }
}
