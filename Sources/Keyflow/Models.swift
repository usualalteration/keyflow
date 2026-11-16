import Foundation

enum Genre: String, CaseIterable, Codable, Identifiable {
    case techno = "TECHNO"
    case dnb = "DRUM & BASS"
    case synthwave = "SYNTHWAVE"
    case ambient = "AMBIENT"
    case experimental = "EXPERIMENTAL"
    var id: String { rawValue }
}

enum ScaleType: String, CaseIterable, Codable, Identifiable {
    case minor = "Minor"
    case major = "Major"
    case dorian = "Dorian"
    case phrygian = "Phrygian"
    case mixolydian = "Mixolydian"
    case lydian = "Lydian"
    case harmonicMinor = "Harmonic Minor"
    case minorPentatonic = "Minor Pentatonic"
    case wholeTone = "Whole Tone"

    var id: String { rawValue }

    var intervals: [Int] {
        switch self {
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: return [0, 1, 3, 5, 7, 8, 10]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        case .lydian: return [0, 2, 4, 6, 7, 9, 11]
        case .harmonicMinor: return [0, 2, 3, 5, 7, 8, 11]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .wholeTone: return [0, 2, 4, 6, 8, 10]
        }
    }
}

enum VisualizationMode: String, CaseIterable, Codable, Identifiable {
    case waveform = "WAVEFORM"
    case spectrum = "SPECTRUM"
    case pulse = "PULSE"
    case equalizer = "EQ"
    var id: String { rawValue }
}

enum Layer: Int, CaseIterable, Identifiable {
    case kick = 0, snare, hats, perc, bass, pad, lead, arp
    var id: Int { rawValue }
    var bit: UInt8 { UInt8(1) << UInt8(rawValue) }
    var title: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare / Clap"
        case .hats: return "Hi-hats"
        case .perc: return "Percussion"
        case .bass: return "Bass"
        case .pad: return "Pads"
        case .lead: return "Lead / Key plucks"
        case .arp: return "Arpeggiator"
        }
    }
}

/// Neon palettes. `primary` is the main accent, `secondary` the companion colour.
enum AccentColor: String, CaseIterable, Codable, Identifiable {
    case lime = "Neon Lime"
    case magenta = "Hot Pink"
    case violet = "Ultraviolet"
    case orange = "Solar Orange"
    case yellow = "Laser Yellow"
    case red = "Laser Red"
    case iceBlue = "Ice Blue"

    var id: String { rawValue }

    var primaryHex: UInt32 {
        switch self {
        case .lime: return 0xB4FF78
        case .magenta: return 0xFF3EA5
        case .violet: return 0xB77CFF
        case .orange: return 0xFF9A2E
        case .yellow: return 0xF4FF4D
        case .red: return 0xFF4060
        case .iceBlue: return 0x4DD8FF
        }
    }

    var secondaryHex: UInt32 {
        switch self {
        case .lime: return 0x4DE3F0
        case .magenta: return 0x4DE3F0
        case .violet: return 0x5EF2E0
        case .orange: return 0xFF4D8D
        case .yellow: return 0x4DE3F0
        case .red: return 0xFFA040
        case .iceBlue: return 0xB77CFF
        }
    }
}

/// Everything the user can tweak. Codable so it can be persisted and stored as a favorite.
/// Decoding tolerates missing keys, so settings saved by older versions keep working.
struct Configuration: Codable, Equatable {
    var genre: Genre = .techno
    var bpm: Double = 128
    var keyRoot: Int = 9
    var scale: ScaleType = .minor
    var intensity: Double = 0.55
    var volume: Double = 0.6
    var sensitivity: Double = 1.0
    var density: Double = 0.6
    var layerMask: UInt8 = 0xFF
    var seed: UInt32 = 1337
    var monitoring: Bool = true
    var visualization: VisualizationMode = .waveform
    var vizSmoothing: Double = 0.6
    var showParticles: Bool = true
    var outputDeviceUID: String = ""
    var accent: AccentColor = .lime
    var randomSeedOnLaunch: Bool = true
    var eqEnabled: Bool = true
    var eqGains: [Double] = Array(repeating: 0, count: 10)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Configuration()
        genre = try c.decodeIfPresent(Genre.self, forKey: .genre) ?? d.genre
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm) ?? d.bpm
        keyRoot = try c.decodeIfPresent(Int.self, forKey: .keyRoot) ?? d.keyRoot
        scale = try c.decodeIfPresent(ScaleType.self, forKey: .scale) ?? d.scale
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? d.intensity
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? d.volume
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        density = try c.decodeIfPresent(Double.self, forKey: .density) ?? d.density
        layerMask = try c.decodeIfPresent(UInt8.self, forKey: .layerMask) ?? d.layerMask
        seed = try c.decodeIfPresent(UInt32.self, forKey: .seed) ?? d.seed
        monitoring = try c.decodeIfPresent(Bool.self, forKey: .monitoring) ?? d.monitoring
        visualization = (try? c.decode(VisualizationMode.self, forKey: .visualization)) ?? d.visualization
        vizSmoothing = try c.decodeIfPresent(Double.self, forKey: .vizSmoothing) ?? d.vizSmoothing
        showParticles = try c.decodeIfPresent(Bool.self, forKey: .showParticles) ?? d.showParticles
        outputDeviceUID = try c.decodeIfPresent(String.self, forKey: .outputDeviceUID) ?? d.outputDeviceUID
        accent = try c.decodeIfPresent(AccentColor.self, forKey: .accent) ?? d.accent
        randomSeedOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .randomSeedOnLaunch) ?? d.randomSeedOnLaunch
        eqEnabled = try c.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? d.eqEnabled
        let g = try c.decodeIfPresent([Double].self, forKey: .eqGains) ?? d.eqGains
        eqGains = g.count == 10 ? g : d.eqGains
    }
}

enum NoteNames {
    static let all = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
}
