import Foundation
import os

/// Parameters read by the audio thread. POD only: no references, no allocation.
struct SynthParams {
    var playing = true
    var bpm: Double = 120
    var swing: Float = 0.06
    var humanize: Float = 0.3
    var keyRoot = 9
    var scaleIndex = 0
    var energy: Float = 0.3
    var complexity: Float = 0.25
    var atmosphere: Float = 0
    var density: Float = 0.6
    var seed: UInt32 = 1
    var layerMask: UInt8 = 0xFF
    var keyHits: UInt32 = 0
    var fillCounter: UInt32 = 0
    var riserCounter: UInt32 = 0
}

/// Main-thread -> audio-thread hand-off. The audio thread only ever *tries* the lock
/// (and keeps its previous values if it is busy), so it can never block.
final class SharedParams {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var params = SynthParams()
    private var profile = GenreProfile.profile(.techno)
    private var profileVersion = 0

    init() { lock.initialize(to: os_unfair_lock()) }
    deinit { lock.deallocate() }

    func mutate(_ f: (inout SynthParams) -> Void) {
        os_unfair_lock_lock(lock)
        f(&params)
        os_unfair_lock_unlock(lock)
    }

    func setProfile(_ p: GenreProfile) {
        os_unfair_lock_lock(lock)
        profile = p
        profileVersion += 1
        os_unfair_lock_unlock(lock)
    }

    /// Audio thread. Returns true if a new genre profile was loaded.
    func pull(into p: inout SynthParams, profile prof: inout GenreProfile, seen: inout Int) -> Bool {
        guard os_unfair_lock_trylock(lock) else { return false }
        p = params
        var changed = false
        if profileVersion != seen {
            prof = profile
            seen = profileVersion
            changed = true
        }
        os_unfair_lock_unlock(lock)
        return changed
    }
}
