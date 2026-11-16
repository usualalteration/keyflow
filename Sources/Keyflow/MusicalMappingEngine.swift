import Foundation

struct MusicalControl {
    var energy: Float = 0.3
    var complexity: Float = 0.25
    var atmosphere: Float = 0
    var swing: Float = 0.06
    var humanize: Float = 0.3
    var fillRequest = false
    var riserRequest = false
}

/// Maps typing descriptors + user settings to musical control values (runs ~30 Hz on the main thread).
///  - typing speed        -> arrangement energy (which layers play)
///  - typing bursts       -> complexity (how many optional notes appear)
///  - inter-key irregularity -> swing + humanization
///  - pauses              -> drum fill + crash; long inactivity -> atmosphere
///  - resuming after a long silence -> riser
/// Typing never changes the master volume.
final class MusicalMappingEngine {
    private var activity: Float = 0
    private var burst: Float = 0
    private var atmosphere: Float = 0.5
    private var energy: Float = 0.3
    private var complexity: Float = 0.25
    private var peakActivity: Float = 0
    private var pauseHandled = true
    private var wasLongIdle = false

    @inline(__always) private func clamp01(_ x: Float) -> Float { min(1, max(0, x)) }
    @inline(__always) private func rate(_ perSecond: Float, _ dt: Float) -> Float { 1 - expf(-perSecond * dt) }

    func update(dt: Float, typing t: TypingRhythmAnalyzer.Snapshot,
                config c: Configuration, profile: GenreProfile) -> MusicalControl {
        let sens = Float(c.sensitivity)
        let kps = 0.65 * t.shortKPS + 0.35 * t.longKPS
        let actTarget = clamp01(kps * sens / 7)
        activity += (actTarget - activity) * rate(actTarget > activity ? 1.8 : 0.25, dt)

        let burstTarget = clamp01((t.shortKPS * sens - 3.5) / 5)
        burst += (burstTarget - burst) * rate(burstTarget > burst ? 3.0 : 0.5, dt)

        let atmTarget = clamp01((t.idleSeconds - 6) / 40)
        atmosphere += (atmTarget - atmosphere) * rate(0.15, dt)

        let floorE = profile.idleFloor * (1 - 0.5 * atmosphere)
        var e = floorE + (1 - floorE) * activity
        e += Float(c.intensity - 0.5) * 0.6
        e = clamp01(e)
        energy += (e - energy) * rate(e > energy ? 0.9 : 0.2, dt)

        let cTarget = clamp01(0.2 + 0.8 * burst + 0.2 * t.groove)
        complexity += (cTarget - complexity) * rate(1.0, dt)

        var ctl = MusicalControl()
        ctl.energy = energy
        ctl.complexity = complexity
        ctl.atmosphere = atmosphere
        ctl.swing = min(0.42, profile.swing + (profile.genre == .ambient ? 0 : t.groove * 0.10))
        ctl.humanize = 0.3 + 0.4 * t.groove

        peakActivity = max(peakActivity, activity)
        if t.idleSeconds > 1.6 && peakActivity > 0.3 && !pauseHandled {
            ctl.fillRequest = true
            pauseHandled = true
        }
        if t.idleSeconds > 12 { wasLongIdle = true }
        if t.idleSeconds < 0.5 {
            if wasLongIdle { ctl.riserRequest = true; wasLongIdle = false }
            pauseHandled = false
            peakActivity = activity
        }
        return ctl
    }
}
