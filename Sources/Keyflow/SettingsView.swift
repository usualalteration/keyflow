import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var audio: AudioEngine
    @EnvironmentObject var presets: PresetManager
    @State private var devices: [AudioOutputDevice] = []
    @State private var favoriteName = ""

    var body: some View {
        Form {
            Section("Keyboard") {
                Toggle("Global keyboard monitoring", isOn: $settings.config.monitoring)
                if settings.config.monitoring && !app.inputAccessGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KEYFLOW needs Input Monitoring permission to read key timing. Grant it in System Settings, then relaunch the app.")
                            .font(.caption).foregroundColor(.orange)
                        Button("Open Input Monitoring settings") { app.openInputMonitoringSettings() }
                    }
                }
                Text("Only anonymous key-down/up timestamps are used. Characters, key codes and text are never read, stored or transmitted.")
                    .font(.caption).foregroundColor(.secondary)
                slider("Typing sensitivity", $settings.config.sensitivity, 0.25...2.5, "×%.2f")
            }

            Section("Music") {
                slider("BPM", $settings.config.bpm, GenreProfile.profile(settings.config.genre).bpmRange, "%.0f")
                slider("Musical density", $settings.config.density, 0...1, "%.2f")
                slider("Intensity", $settings.config.intensity, 0...1, "%.2f")
                slider("Volume", $settings.config.volume, 0...1, "%.2f")
                Picker("Key", selection: $settings.config.keyRoot) {
                    ForEach(0..<12, id: \.self) { Text(NoteNames.all[$0]).tag($0) }
                }
                Picker("Scale", selection: $settings.config.scale) {
                    ForEach(ScaleType.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("Random seed")
                    TextField("", value: $settings.config.seed, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                    Button("Randomize") { settings.randomizeSeed() }
                }
                Toggle("New random melody at each launch", isOn: $settings.config.randomSeedOnLaunch)
            }

            Section("Instruments") {
                ForEach(Layer.allCases) { l in
                    Toggle(l.title, isOn: Binding(get: { settings.isEnabled(l) },
                                                  set: { settings.setEnabled(l, $0) }))
                }
            }

            Section("Audio output") {
                Picker("Device", selection: $settings.config.outputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                Button("Refresh devices") { devices = AudioDevices.outputDevices() }
            }

            Section("Appearance") {
                HStack(spacing: 12) {
                    ForEach(AccentColor.allCases) { a in
                        Button { settings.config.accent = a } label: {
                            Circle().fill(Color(hex: a.primaryHex))
                                .frame(width: 24, height: 24)
                                .shadow(color: Color(hex: a.primaryHex).opacity(0.8), radius: 5)
                                .overlay(Circle().stroke(Color.white, lineWidth: settings.config.accent == a ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .help(a.rawValue)
                    }
                }
            }

            Section("Visualization") {
                Picker("Mode", selection: $settings.config.visualization) {
                    ForEach(VisualizationMode.allCases) { Text($0.rawValue).tag($0) }
                }
                slider("Smoothing", $settings.config.vizSmoothing, 0...1, "%.2f")
                Toggle("Particles (Pulse mode)", isOn: $settings.config.showParticles)
            }

            Section("Favorites") {
                HStack {
                    TextField("Name", text: $favoriteName)
                    Button("Save current") {
                        presets.add(name: favoriteName, config: settings.config)
                        favoriteName = ""
                    }
                }
                ForEach(presets.favorites) { fav in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(fav.name)
                            Text("\(fav.config.genre.rawValue) · \(Int(fav.config.bpm)) BPM · seed \(fav.config.seed)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Load") { settings.config = fav.config }
                        Button(role: .destructive) { presets.remove(fav) } label: { Image(systemName: "trash") }
                    }
                }
            }

            Section("About") {
                Text("KEYFLOW \(AppInfo.version)").foregroundColor(.secondary)
                Link("Support KEYFLOW on Ko-fi ☕", destination: AppInfo.koFiURL)
                Button("Uninstall KEYFLOW…", role: .destructive) { app.confirmUninstall() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .frame(minWidth: 520, minHeight: 600)
        .onAppear { devices = AudioDevices.outputDevices() }
        .id(settings.config.accent)
    }

    private func slider(_ title: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ format: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range).tint(Theme.accent)
            Text(String(format: format, value.wrappedValue))
                .font(Theme.mono).foregroundColor(Theme.accent).frame(width: 52, alignment: .trailing)
        }
    }
}
