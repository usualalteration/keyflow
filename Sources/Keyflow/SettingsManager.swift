import Foundation
import Combine

final class SettingsManager: ObservableObject {
    @Published var config: Configuration {
        didSet { save(); Theme.apply(config.accent) }
    }
    private let key = "keyflow.config.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: "keyflow.config.v1"),
           let c = try? JSONDecoder().decode(Configuration.self, from: data) {
            config = c
        } else {
            config = Configuration()
        }
        if config.randomSeedOnLaunch { config.seed = UInt32.random(in: 1...999_999_999) }
        Theme.apply(config.accent)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Selecting a genre loads that genre's default tempo, key and scale.
    func selectGenre(_ g: Genre) {
        let p = GenreProfile.profile(g)
        var c = config
        c.genre = g
        c.bpm = p.defaultBPM
        c.keyRoot = p.defaultKey
        c.scale = p.defaultScale
        c.intensity = p.defaultIntensity
        config = c
    }

    func isEnabled(_ l: Layer) -> Bool { config.layerMask & l.bit != 0 }

    func setEnabled(_ l: Layer, _ on: Bool) {
        if on { config.layerMask |= l.bit } else { config.layerMask &= ~l.bit }
    }

    func randomizeSeed() { config.seed = UInt32.random(in: 1...999_999_999) }
}
