import SwiftUI

@main
struct KeyflowApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("KEYFLOW", id: "main") {
            ContentView()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.audio)
                .environmentObject(app.recorder)
                .environmentObject(app.presets)
                .preferredColorScheme(.dark)
                .onAppear { app.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Support KEYFLOW on Ko-fi ☕") { NSWorkspace.shared.open(AppInfo.koFiURL) }
                Button("Uninstall KEYFLOW…") { app.confirmUninstall() }
            }
        }

        Window("KEYFLOW Settings", id: "settings") {
            SettingsView()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.audio)
                .environmentObject(app.presets)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 560, height: 720)

        MenuBarExtra("KEYFLOW", systemImage: "waveform") {
            MenuBarContent()
                .environmentObject(app)
                .environmentObject(app.settings)
                .environmentObject(app.audio)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var audio: AudioEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(audio.isPlaying ? "Pause" : "Play") { app.togglePlay() }
        Toggle("Global keyboard monitoring", isOn: $settings.config.monitoring)
        Divider()
        Button("Open KEYFLOW") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Support on Ko-fi ☕") { NSWorkspace.shared.open(AppInfo.koFiURL) }
        Divider()
        Button("Uninstall KEYFLOW…") { app.confirmUninstall() }
        Button("Quit KEYFLOW") { NSApp.terminate(nil) }
    }
}
