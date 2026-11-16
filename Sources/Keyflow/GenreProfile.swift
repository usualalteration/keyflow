import Foundation

/// Everything that makes a genre sound and behave differently: synthesis parameters,
/// rhythm patterns, chord progressions and arrangement thresholds.
struct GenreProfile {
    var genre: Genre = .techno
    var defaultBPM: Double = 128
    var bpmRange: ClosedRange<Double> = 110...150
    var defaultKey: Int = 9
    var defaultScale: ScaleType = .minor
    var defaultIntensity: Double = 0.55
    var swing: Float = 0.06
    /// Arrangement energy the music falls back to when typing stops.
    var idleFloor: Float = 0.3

    // Arrangement: layer is active when energy >= threshold. Order follows `Layer`:
    // kick, snare, hats, perc, bass, pad, lead, arp
    var thresholds: [Float] = [0.25, 0.48, 0.12, 0.40, 0.33, 0.0, 0.72, 0.62]
    var levels: [Float] = [1.0, 0.75, 0.55, 0.5, 0.85, 0.5, 0.45, 0.4]

    // 16-step patterns
    var kick = [Float](repeating: 0, count: 16)
    var snare = [Float](repeating: 0, count: 16)
    var hat = [Float](repeating: 0, count: 16)
    var openHat = [Float](repeating: 0, count: 16)
    var perc = [Float](repeating: 0, count: 16)
    var bass = [Float](repeating: 0, count: 16)
    var randomized = false

    // Harmony
    var barsPerChord = 2
    var progressions: [[Int]] = [[0, 0, 5, 6]]

    // Kick
    var kickF0: Float = 170, kickF1: Float = 48, kickPitchDecay: Float = 0.035
    var kickDecay: Float = 0.32, kickDrive: Float = 1.8, kickClick: Float = 0.3
    // Snare
    var snareFreq: Float = 190, snareDecay: Float = 0.18, snareNoise: Float = 0.8, snareTone: Float = 0.5
    // Hats
    var hatDecay: Float = 0.045, openDecay: Float = 0.16
    // Perc (2-op FM)
    var percDecay: Float = 0.12, percPitchMul: Float = 2.2, fmIndex: Float = 1.5, fmRatio: Float = 1.5
    var percOctave = 4
    // Bass
    var bassWave = 0, bassCutoff: Float = 160, bassCutoffAmt: Float = 1800, bassCutoffDecay: Float = 0.10
    var bassDecay: Float = 0.14, bassHoldSteps: Float = 0, bassSub: Float = 0.5, bassOctave = 1
    var bassGlide: Float = 0, bassDetune: Float = 0.004, bassVariety: Float = 0.25
    // Lead
    var leadWave = 1, leadCutoff: Float = 900, leadCutoffAmt: Float = 2500, leadCutoffDecay: Float = 0.15
    var leadDecay: Float = 0.25, leadProb: Float = 0.3, leadOctave = 4, leadDetune: Float = 0.006
    // Arp / key plucks
    var arpDiv = 1, arpWave = 0, arpDecay: Float = 0.12, arpCutoff: Float = 700, arpCutoffAmt: Float = 3500
    var arpOctave = 1
    // Pad
    var padCutoff: Float = 900, padDetune: Float = 0.006
    // FX
    var delayBeats: Float = 0.75, delayFeedback: Float = 0.42, delaySend: Float = 0.25
    var reverbSend: Float = 0.12, reverbFeedback: Float = 0.78

    private static let cache: [Genre: GenreProfile] = {
        var d: [Genre: GenreProfile] = [:]
        for g in Genre.allCases { d[g] = build(g) }
        return d
    }()

    static func profile(_ g: Genre) -> GenreProfile { cache[g]! }

    private static func build(_ g: Genre) -> GenreProfile {
        var p = GenreProfile()
        p.genre = g
        switch g {
        case .techno:
            p.defaultBPM = 128; p.bpmRange = 112...150; p.defaultKey = 9; p.defaultScale = .minor
            p.defaultIntensity = 0.55; p.swing = 0.06; p.idleFloor = 0.30
            p.thresholds = [0.25, 0.48, 0.12, 0.40, 0.33, 0.0, 0.72, 0.62]
            p.levels = [1.0, 0.75, 0.55, 0.5, 0.85, 0.5, 0.45, 0.4]
            p.kick    = [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0]
            p.snare   = [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0.3]
            p.hat     = [0,0.5,0,0.5, 0,0.5,0,0.5, 0,0.5,0,0.5, 0,0.5,0,0.6]
            p.openHat = [0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0]
            p.perc    = [0,0,0.3,0, 0,0.4,0,0.3, 0,0,0.3,0, 0,0.4,0,0.5]
            p.bass    = [0,0.3,1,0.5, 0,0.3,1,0.5, 0,0.3,1,0.5, 0,0.3,1,0.5]
            p.barsPerChord = 2
            p.progressions = [[0, 0, 5, 6], [0, 5, 0, 6], [0, 3, 5, 4]]
        case .dnb:
            p.defaultBPM = 174; p.bpmRange = 150...190; p.defaultKey = 4; p.defaultScale = .minor
            p.defaultIntensity = 0.6; p.swing = 0.03; p.idleFloor = 0.30
            p.thresholds = [0.20, 0.40, 0.10, 0.35, 0.28, 0.0, 0.70, 0.58]
            p.levels = [1.0, 0.8, 0.5, 0.45, 0.9, 0.45, 0.45, 0.4]
            p.kick    = [1,0,0,0, 0,0,0,0, 0,0,1,0, 0,0,0,0]
            p.snare   = [0,0,0,0, 1,0,0,0.3, 0,0,0.2,0, 1,0,0,0.4]
            p.hat     = [0.4,0.3,1,0.3, 0.4,0.3,1,0.3, 0.4,0.3,1,0.3, 0.4,0.3,1,0.3]
            p.openHat = [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0.35,0]
            p.perc    = [0,0,0.3,0, 0,0,0,0.3, 0,0.3,0,0, 0,0,0.3,0]
            p.bass    = [1,0,0,0.5, 0,0,0.6,0, 0,0,1,0, 0,0.4,0,0.5]
            p.barsPerChord = 2
            p.progressions = [[0, 5, 2, 6], [0, 0, 3, 6]]
            p.kickF0 = 150; p.kickF1 = 52; p.kickDecay = 0.26; p.kickDrive = 1.5
            p.snareFreq = 210; p.snareDecay = 0.15; p.hatDecay = 0.035
            p.bassWave = 0; p.bassCutoff = 300; p.bassCutoffAmt = 1500; p.bassCutoffDecay = 0.25
            p.bassDecay = 0.35; p.bassHoldSteps = 2; p.bassSub = 0.7; p.bassOctave = 1
            p.bassDetune = 0.012; p.bassGlide = 0.004; p.bassVariety = 0.2
            p.leadWave = 0; p.leadCutoff = 1200; p.leadCutoffAmt = 2500; p.leadDecay = 0.3; p.leadProb = 0.25
            p.arpDiv = 1; p.arpDecay = 0.09; p.arpOctave = 1
            p.padCutoff = 1100; p.delayBeats = 0.75; p.delayFeedback = 0.4; p.delaySend = 0.22
            p.reverbSend = 0.15; p.reverbFeedback = 0.8
        case .synthwave:
            p.defaultBPM = 100; p.bpmRange = 80...125; p.defaultKey = 4; p.defaultScale = .minor
            p.defaultIntensity = 0.55; p.swing = 0.04; p.idleFloor = 0.30
            p.thresholds = [0.22, 0.40, 0.10, 0.50, 0.30, 0.0, 0.55, 0.45]
            p.levels = [0.95, 0.85, 0.45, 0.4, 0.8, 0.7, 0.55, 0.45]
            p.kick    = [1,0,0,0, 0,0,0,0, 1,0,0.4,0, 0,0,0.3,0]
            p.snare   = [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]
            p.hat     = [1,0.3,1,0.3, 1,0.3,1,0.3, 1,0.3,1,0.3, 1,0.3,1,0.3]
            p.openHat = [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0.5,0]
            p.perc    = [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0.3,0,0.3]
            p.bass    = [1,0,1,0.3, 1,0,1,0.3, 1,0,1,0.3, 1,0,1,0.3]
            p.barsPerChord = 1
            p.progressions = [[0, 5, 2, 6], [5, 6, 0, 0], [0, 6, 5, 6]]
            p.kickF0 = 140; p.kickF1 = 50; p.kickDecay = 0.30; p.kickDrive = 1.4; p.kickClick = 0.15
            p.snareFreq = 200; p.snareDecay = 0.26; p.snareNoise = 0.85; p.snareTone = 0.45
            p.hatDecay = 0.05
            p.bassWave = 0; p.bassCutoff = 500; p.bassCutoffAmt = 1600; p.bassCutoffDecay = 0.12
            p.bassDecay = 0.20; p.bassHoldSteps = 1; p.bassSub = 0.3; p.bassOctave = 1
            p.bassDetune = 0.008; p.bassVariety = 0.5
            p.leadWave = 0; p.leadCutoff = 1500; p.leadCutoffAmt = 3000; p.leadDecay = 0.5
            p.leadProb = 0.45; p.leadOctave = 4; p.leadDetune = 0.01
            p.arpDiv = 2; p.arpWave = 0; p.arpDecay = 0.2; p.arpCutoff = 900; p.arpOctave = 1
            p.padCutoff = 1500; p.padDetune = 0.01
            p.delayBeats = 0.75; p.delayFeedback = 0.5; p.delaySend = 0.35
            p.reverbSend = 0.25; p.reverbFeedback = 0.84
        case .ambient:
            p.defaultBPM = 72; p.bpmRange = 50...100; p.defaultKey = 0; p.defaultScale = .lydian
            p.defaultIntensity = 0.45; p.swing = 0.0; p.idleFloor = 0.12
            p.thresholds = [0.70, 0.90, 0.30, 0.22, 0.15, 0.0, 0.18, 0.40]
            p.levels = [0.5, 0.4, 0.3, 0.4, 0.6, 0.9, 0.5, 0.35]
            p.kick    = [1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0]
            p.hat     = [0,0,0.5,0, 0,0,0.4,0, 0,0,0.5,0, 0,0,0.4,0]
            p.perc    = [0,0,0,0.4, 0,0,0,0.3, 0,0,0.3,0, 0,0,0,0.4]
            p.bass    = [1,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0.5,0]
            p.barsPerChord = 2
            p.progressions = [[0, 3, 4, 0], [0, 5, 3, 4]]
            p.kickF0 = 90; p.kickF1 = 42; p.kickDecay = 0.5; p.kickDrive = 1.0; p.kickClick = 0
            p.hatDecay = 0.06; p.percDecay = 0.4; p.fmIndex = 0.8; p.fmRatio = 2.0
            p.bassWave = 2; p.bassCutoff = 300; p.bassCutoffAmt = 200; p.bassDecay = 1.2
            p.bassHoldSteps = 4; p.bassSub = 0; p.bassOctave = 1; p.bassDetune = 0; p.bassVariety = 0.1
            p.leadWave = 3; p.leadCutoff = 2500; p.leadCutoffAmt = 1500; p.leadDecay = 1.5
            p.leadProb = 0.3; p.leadOctave = 5; p.leadDetune = 0.004
            p.arpDiv = 4; p.arpWave = 3; p.arpDecay = 0.6; p.arpCutoff = 1800; p.arpCutoffAmt = 1200; p.arpOctave = 1
            p.padCutoff = 1400; p.padDetune = 0.01
            p.delayBeats = 1.5; p.delayFeedback = 0.55; p.delaySend = 0.4
            p.reverbSend = 0.45; p.reverbFeedback = 0.88
        case .experimental:
            p.defaultBPM = 110; p.bpmRange = 70...170; p.defaultKey = 2; p.defaultScale = .phrygian
            p.defaultIntensity = 0.55; p.swing = 0.12; p.idleFloor = 0.25
            p.thresholds = [0.20, 0.35, 0.10, 0.18, 0.30, 0.0, 0.45, 0.50]
            p.levels = [0.9, 0.7, 0.45, 0.6, 0.75, 0.5, 0.5, 0.4]
            p.randomized = true
            p.barsPerChord = 1
            p.progressions = [[0, 1, 0, 6], [0, 3, 1, 5], [0, 6, 3, 1]]
            p.kickF0 = 220; p.kickF1 = 38; p.kickPitchDecay = 0.06; p.kickDecay = 0.4; p.kickDrive = 2.4; p.kickClick = 0.5
            p.snareFreq = 260; p.snareDecay = 0.12; p.snareNoise = 0.9
            p.hatDecay = 0.03
            p.percDecay = 0.22; p.percPitchMul = 3.0; p.fmIndex = 4.0; p.fmRatio = 2.76
            p.bassWave = 1; p.bassCutoff = 250; p.bassCutoffAmt = 3500; p.bassCutoffDecay = 0.06
            p.bassDecay = 0.18; p.bassSub = 0.4; p.bassOctave = 1; p.bassGlide = 0.01; p.bassVariety = 0.5
            p.leadWave = 4; p.leadCutoff = 3000; p.leadCutoffAmt = 2000; p.leadDecay = 0.4; p.leadProb = 0.5
            p.arpDiv = 1; p.arpWave = 3; p.arpDecay = 0.08; p.arpCutoff = 1500; p.arpCutoffAmt = 3000
            p.padCutoff = 1100; p.padDetune = 0.02
            p.delayBeats = 0.5; p.delayFeedback = 0.6; p.delaySend = 0.35
            p.reverbSend = 0.3; p.reverbFeedback = 0.82
        }
        return p
    }
}
