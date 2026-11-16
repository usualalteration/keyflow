import Foundation

/// Step-pattern logic. Patterns hold probabilities: 1 = always (when the layer is on),
/// fractions are "extra" notes that appear as typing complexity / user density rise.
enum RhythmEngine {
    /// Hit densities used by the EXPERIMENTAL preset, which generates new patterns every two bars.
    /// Order: kick, snare, hat, openHat, perc, bass
    static let generatedDensity: [Float] = [0.28, 0.20, 0.50, 0.15, 0.40, 0.32]

    @inline(__always)
    static func probability(_ pattern: [Float], kind: Int, randomized: Bool,
                            step: Int, bar: Int, seed: UInt32) -> Float {
        if randomized {
            if kind == 0 && step == 0 && bar % 2 == 0 { return 1 }
            let r = hash01(seed, UInt32(truncatingIfNeeded: bar / 2), UInt32(kind * 16 + step + 3000))
            let d = generatedDensity[kind]
            if r < d { return 1 }
            if r < d * 1.5 { return 0.4 }
            return 0
        }
        return pattern[step]
    }

    @inline(__always)
    static func hit(_ prob: Float, salt: Int, step: Int, bar: Int, seed: UInt32,
                    complexity: Float, density: Float) -> Bool {
        if prob >= 0.99 { return true }
        if prob <= 0.001 { return false }
        let r = hash01(seed, UInt32(truncatingIfNeeded: bar), UInt32(step * 16 + salt))
        return r < prob * complexity * (0.4 + 1.2 * density)
    }
}
