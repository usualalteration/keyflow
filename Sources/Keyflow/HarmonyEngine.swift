import Foundation

/// Stateless hashing so that every "random" musical decision is a pure function of
/// (seed, bar, step, salt). That is what makes a seed reproducible.
@inline(__always)
func hash32(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32 {
    var h = a &* 0x9E3779B1
    h ^= (b &+ 0x7F4A7C15) &* 0x85EBCA6B
    h = (h << 13) | (h >> 19)
    h ^= (c &+ 0x165667B1) &* 0xC2B2AE35
    h ^= h >> 15
    h = h &* 0x2C1B3C6D
    h ^= h >> 12
    h = h &* 0x297A2D39
    h ^= h >> 15
    return h
}

@inline(__always)
func hash01(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> Float {
    Float(hash32(a, b, c) >> 8) / 16777216.0
}

/// Scales, chords and quantization. All functions are allocation-free.
enum HarmonyEngine {
    static let scaleTable: [[Int]] = ScaleType.allCases.map { $0.intervals }

    @inline(__always)
    static func scaleCount(_ scaleIndex: Int) -> Int { scaleTable[scaleIndex].count }

    /// MIDI note for an (unbounded, possibly negative) scale step.
    @inline(__always)
    static func scaleNote(step: Int, root: Int, octave: Int, scaleIndex: Int) -> Int {
        let iv = scaleTable[scaleIndex]
        let n = iv.count
        var oct = step / n
        var idx = step % n
        if idx < 0 { idx += n; oct -= 1 }
        return 12 * (octave + 1) + root + 12 * oct + iv[idx]
    }

    /// Triad-plus-seventh built by stacking scale thirds on a degree.
    static func chord(degree: Int, root: Int, octave: Int, scaleIndex: Int) -> (Int, Int, Int, Int) {
        (scaleNote(step: degree, root: root, octave: octave, scaleIndex: scaleIndex),
         scaleNote(step: degree + 2, root: root, octave: octave, scaleIndex: scaleIndex),
         scaleNote(step: degree + 4, root: root, octave: octave, scaleIndex: scaleIndex),
         scaleNote(step: degree + 6, root: root, octave: octave, scaleIndex: scaleIndex))
    }

    /// Snap any MIDI note to the nearest note of the scale.
    static func quantize(midi: Int, root: Int, scaleIndex: Int) -> Int {
        let iv = scaleTable[scaleIndex]
        var best = midi
        var bestDist = Int.max
        for oct in -1...1 {
            for i in iv {
                let candidate = ((midi - root) / 12 + oct) * 12 + root + i
                let d = abs(candidate - midi)
                if d < bestDist { bestDist = d; best = candidate }
            }
        }
        return best
    }

    @inline(__always)
    static func hz(_ midi: Int) -> Float {
        440.0 * powf(2.0, Float(midi - 69) / 12.0)
    }
}
