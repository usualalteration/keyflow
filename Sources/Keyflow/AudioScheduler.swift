import Foundation

/// Sample-accurate 16th-note clock with swing. Lives entirely on the audio thread.
struct AudioScheduler {
    var samplesToNext: Double = 0
    var step: Int = 0      // next step to fire (0...15)
    var bar: Int = 0

    /// Call right after firing `step`; schedules the following one.
    mutating func consume(bpm: Double, swing: Double, sampleRate: Double) {
        let base = 60.0 / max(20.0, bpm) / 4.0 * sampleRate
        samplesToNext += (step % 2 == 0) ? base * (1.0 + swing) : base * (1.0 - swing)
        step += 1
        if step == 16 { step = 0; bar += 1 }
    }
}
