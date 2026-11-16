import Foundation

/// Turns anonymous key-down/up timestamps into rhythm descriptors.
/// Stores nothing but timestamps (and only the last ~10 seconds of them).
final class TypingRhythmAnalyzer {
    struct Snapshot {
        var shortKPS: Float = 0      // keys/second over ~1.5 s
        var longKPS: Float = 0       // keys/second over ~8 s
        var groove: Float = 0        // 0 = metronomic, 1 = very irregular
        var idleSeconds: Float = 999
        var keysDown: Int = 0
        var totalKeys: Int = 0
    }

    private let lock = NSLock()
    private var downs: [Double] = []
    private var intervals: [Double] = []
    private var lastDown: Double = -1
    private var keysDown = 0
    private var total = 0

    func registerDown(at t: Double) {
        lock.lock(); defer { lock.unlock() }
        if lastDown > 0 {
            let dt = t - lastDown
            if dt < 2.0 {
                intervals.append(dt)
                if intervals.count > 16 { intervals.removeFirst() }
            }
        }
        lastDown = t
        downs.append(t)
        while let f = downs.first, t - f > 10 { downs.removeFirst() }
        keysDown += 1
        total += 1
    }

    func registerUp() {
        lock.lock(); defer { lock.unlock() }
        keysDown = max(0, keysDown - 1)
    }

    func snapshot(now: Double) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        var s = Snapshot()
        var short = 0, long = 0
        for d in downs {
            let age = now - d
            if age <= 1.5 { short += 1 }
            if age <= 8.0 { long += 1 }
        }
        s.shortKPS = Float(short) / 1.5
        s.longKPS = Float(long) / 8.0
        s.idleSeconds = lastDown < 0 ? 999 : Float(max(0, now - lastDown))
        if s.idleSeconds > 2 { keysDown = 0 }
        s.keysDown = keysDown
        s.totalKeys = total
        if intervals.count >= 4 {
            let mean = intervals.reduce(0, +) / Double(intervals.count)
            let varc = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count)
            let cv = mean > 0 ? sqrt(varc) / mean : 0
            s.groove = Float(min(1, cv / 0.9))
        }
        return s
    }
}
