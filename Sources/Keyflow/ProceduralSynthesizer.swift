import Foundation

@inline(__always)
private func polyBlep(_ t: Float, _ dt: Float) -> Float {
    if t < dt {
        let x = t / dt
        return x + x - x * x - 1
    } else if t > 1 - dt {
        let x = (t - 1) / dt
        return x * x + x + x + 1
    }
    return 0
}

/// Band-limited oscillator bank. 0 saw, 1 square, 2 sine, 3 triangle, 4 FM bell.
@inline(__always)
func oscillator(_ wave: Int, _ ph: Float, _ dt: Float) -> Float {
    switch wave {
    case 0:
        return (2 * ph - 1) - polyBlep(ph, dt)
    case 1:
        var v: Float = ph < 0.5 ? 1 : -1
        v += polyBlep(ph, dt)
        var p2 = ph + 0.5
        if p2 >= 1 { p2 -= 1 }
        v -= polyBlep(p2, dt)
        return v
    case 2:
        return sinf(2 * Float.pi * ph)
    case 3:
        return 4 * abs(ph - 0.5) - 1
    default:
        return sinf(2 * Float.pi * (ph + 1.2 * sinf(4 * Float.pi * ph)))
    }
}

@inline(__always)
func softClip(_ x: Float) -> Float {
    let a = abs(x)
    if a < 0.8 { return x }
    let y = 0.8 + 0.2 * tanhf((a - 0.8) / 0.2)
    return x < 0 ? -y : y
}

/// Mono subtractive voice used for bass, lead, arp and key plucks.
final class SynthVoice {
    var wave = 0
    var detune: Float = 0
    var subLevel: Float = 0
    var cutoffBase: Float = 500
    var cutoffAmt: Float = 2000
    var cutoffDecayCoef: Float = 0.999
    var decayCoef: Float = 0.9995
    var glide: Float = 1
    var attackSamples = 48

    private var phase1: Float = 0, phase2: Float = 0, phaseSub: Float = 0
    private var freq: Float = 110, targetFreq: Float = 110
    private var env: Float = 0, cutoffEnv: Float = 0, vel: Float = 1
    private var hold = 0, age = 0
    private var lp1: Float = 0, lp2: Float = 0

    var level: Float { env }

    func setup(wave: Int, cutoff: Float, cutoffAmt: Float, cutoffDecay: Float, decay: Float,
               detune: Float, sub: Float, glideSec: Float, sr: Float) {
        self.wave = wave
        self.cutoffBase = cutoff
        self.cutoffAmt = cutoffAmt
        self.cutoffDecayCoef = expf(-1 / (sr * max(0.005, cutoffDecay)))
        self.decayCoef = expf(-1 / (sr * max(0.01, decay)))
        self.detune = detune
        self.subLevel = sub
        self.glide = glideSec <= 0 ? 1 : min(1, 1 - expf(-1 / (sr * glideSec)))
    }

    func trigger(freq f: Float, vel v: Float, holdSamples: Int) {
        targetFreq = f
        if glide >= 1 || env < 0.01 { freq = f }
        vel = v
        env = 1
        hold = holdSamples
        cutoffEnv = 1
        age = 0
    }

    @inline(__always)
    func next(sr: Float, invSr: Float) -> Float {
        if env < 0.0004 { return 0 }
        freq += (targetFreq - freq) * glide
        let dt1 = freq * invSr
        let dt2 = freq * (1 + detune) * invSr
        phase1 += dt1; if phase1 >= 1 { phase1 -= 1 }
        phase2 += dt2; if phase2 >= 1 { phase2 -= 1 }
        phaseSub += dt1 * 0.5; if phaseSub >= 1 { phaseSub -= 1 }
        var s = oscillator(wave, phase1, dt1)
        if detune != 0 { s = 0.5 * (s + oscillator(wave, phase2, dt2)) }
        if subLevel > 0 { s += subLevel * sinf(2 * Float.pi * phaseSub) }
        let fc = min(cutoffBase + cutoffAmt * cutoffEnv, 0.45 * sr)
        let a = 1 - expf(-2 * Float.pi * fc * invSr)
        lp1 += a * (s - lp1)
        lp2 += a * (lp1 - lp2)
        cutoffEnv *= cutoffDecayCoef
        var amp = env * vel
        if age < attackSamples { amp *= Float(age) / Float(attackSamples) }
        age += 1
        if hold > 0 { hold -= 1 } else { env *= decayCoef }
        return lp2 * amp * 0.5
    }
}

/// Small stereo reverb (8 damped combs + 2 all-passes). Buffers are allocated once.
final class MiniReverb {
    private let combLens: [Int]
    private let combs: [UnsafeMutablePointer<Float>]
    private var combIdx: [Int]
    private var combState: [Float]
    private let apLens: [Int]
    private let aps: [UnsafeMutablePointer<Float>]
    private var apIdx: [Int]

    init(sampleRate: Float) {
        let scale = sampleRate / 44100
        let base = [1116, 1188, 1277, 1356, 1139, 1211, 1300, 1379]
        let lens = base.map { Int(Float($0) * scale) }
        combLens = lens
        combs = lens.map { n in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        combIdx = [Int](repeating: 0, count: 8)
        combState = [Float](repeating: 0, count: 8)
        let apl = [Int(556 * scale), Int(441 * scale)]
        apLens = apl
        aps = apl.map { n in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        apIdx = [0, 0]
    }

    deinit {
        combs.forEach { $0.deallocate() }
        aps.forEach { $0.deallocate() }
    }

    @inline(__always)
    func process(_ x: Float, feedback: Float) -> (Float, Float) {
        var outL: Float = 0, outR: Float = 0
        for k in 0..<8 {
            let buf = combs[k]
            let i = combIdx[k]
            let y = buf[i]
            combState[k] = y * 0.6 + combState[k] * 0.4
            buf[i] = x + combState[k] * feedback
            combIdx[k] = i + 1 == combLens[k] ? 0 : i + 1
            if k < 4 { outL += y } else { outR += y }
        }
        outL *= 0.25; outR *= 0.25
        for k in 0..<2 {
            let buf = aps[k]
            let i = apIdx[k]
            let bo = buf[i]
            let inL = k == 0 ? outL : outR
            let o = -inL + bo
            buf[i] = inL + bo * 0.5
            apIdx[k] = i + 1 == apLens[k] ? 0 : i + 1
            if k == 0 { outL = o } else { outR = o }
        }
        return (outL, outR)
    }
}

struct SynthMeters {
    var drums: Float = 0
    var bass: Float = 0
    var melody: Float = 0
    var kickCount: UInt32 = 0
    var quarterCount: UInt32 = 0
}

/// The whole generative instrument. `render` runs on the CoreAudio render thread:
/// no locks (only a try-lock), no allocation, no Objective-C, no I/O.
final class SynthCore {
    let sr: Float
    private let invSr: Float
    private let shared: SharedParams
    private var p = SynthParams()
    private var profile: GenreProfile
    private var seenVersion = -1
    private var sched = AudioScheduler()

    private var lastKey = -1, lastScale = -1
    private var degree = 0
    private var lastKeyHits: UInt32 = 0
    private var lastFill: UInt32 = 0, lastRiser: UInt32 = 0
    private var fillArmed = false, fillActive = false, crashPending = false
    private var runGain: Float = 0
    private var rng: UInt32 = 0x1234ABCD
    private var pluckRR = 0

    // Layer gains
    private let layerGain: UnsafeMutablePointer<Float>
    private let layerTarget: UnsafeMutablePointer<Float>
    private let layerSlew: Float

    // Chord / pad
    private let chordMidi: UnsafeMutablePointer<Int>
    private let padFreq: UnsafeMutablePointer<Float>
    private let padTarget: UnsafeMutablePointer<Float>
    private let padPhA: UnsafeMutablePointer<Float>
    private let padPhB: UnsafeMutablePointer<Float>
    private let padGlide: Float
    private var padL1: Float = 0, padL2: Float = 0, padR1: Float = 0, padR2: Float = 0
    private var padLFO: Float = 0

    // Drum voices
    private var kickEnv: Float = 0, kickPitch: Float = 0, kickPhase: Float = 0
    private var kickAmpC: Float = 0.999, kickPitchC: Float = 0.99
    private var snareEnvN: Float = 0, snareEnvT: Float = 0, snarePhase: Float = 0, snareVel: Float = 1
    private var snareLP: Float = 0, snareNC: Float = 0.999, snareTC: Float = 0.99
    private var hatEnv: Float = 0, openEnv: Float = 0, hatLP: Float = 0
    private var hatC: Float = 0.99, openC: Float = 0.999
    private var percEnv: Float = 0, percPitch: Float = 0, percPhase: Float = 0, percMod: Float = 0
    private var percF0: Float = 200, percF1: Float = 100, percVel: Float = 1
    private var percC: Float = 0.999, percPitchC: Float = 0.998
    private var crashEnv: Float = 0, crashLP: Float = 0, crashC: Float = 0.9999
    private var riserLeft = 0, riserLen = 1
    private var riserLP: Float = 0

    // Synth voices
    private let bass = SynthVoice()
    private let lead = SynthVoice()
    private let arp = SynthVoice()
    private let plucks: [SynthVoice] = [SynthVoice(), SynthVoice(), SynthVoice(), SynthVoice()]

    // FX
    private let reverb: MiniReverb
    private let delayL: UnsafeMutablePointer<Float>
    private let delayR: UnsafeMutablePointer<Float>
    private let delaySize: Int
    private var delayWrite = 0
    private var delaySamples: Float = 20000
    private var limEnv: Float = 0

    // Meters (read by UI; benign races on aligned scalars)
    private var mDrums: Float = 0, mBass: Float = 0, mMelody: Float = 0
    private(set) var kickCount: UInt32 = 0
    private(set) var quarterCount: UInt32 = 0

    private static let arpOrder: [Int] = [0, 1, 2, 3, 2, 1, 3, 2]
    private static let leadOffsets: [Int] = [0, 2, 4, 1, 3, 5, 4, 2]

    init(sampleRate: Float, shared: SharedParams) {
        sr = sampleRate
        invSr = 1 / sampleRate
        self.shared = shared
        profile = GenreProfile.profile(.techno)
        layerSlew = 1 - expf(-1 / (sampleRate * 0.4))
        padGlide = 1 - expf(-1 / (sampleRate * 0.08))
        reverb = MiniReverb(sampleRate: sampleRate)
        delaySize = Int(sampleRate * 3)

        func alloc(_ n: Int) -> UnsafeMutablePointer<Float> {
            let q = UnsafeMutablePointer<Float>.allocate(capacity: n)
            q.initialize(repeating: 0, count: n)
            return q
        }
        layerGain = alloc(8)
        layerTarget = alloc(8)
        padFreq = alloc(4); padTarget = alloc(4); padPhA = alloc(4); padPhB = alloc(4)
        delayL = alloc(Int(sampleRate * 3)); delayR = alloc(Int(sampleRate * 3))
        chordMidi = UnsafeMutablePointer<Int>.allocate(capacity: 4)
        chordMidi.initialize(repeating: 60, count: 4)
        _ = HarmonyEngine.scaleTable.count   // force table init off the audio thread
        _ = RhythmEngine.generatedDensity.count
        configure()
    }

    deinit {
        layerGain.deallocate(); layerTarget.deallocate()
        padFreq.deallocate(); padTarget.deallocate(); padPhA.deallocate(); padPhB.deallocate()
        delayL.deallocate(); delayR.deallocate(); chordMidi.deallocate()
    }

    func meters() -> SynthMeters {
        SynthMeters(drums: mDrums, bass: mBass, melody: mMelody, kickCount: kickCount, quarterCount: quarterCount)
    }

    @inline(__always)
    private func noise() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) / 2147483648.0
    }

    @inline(__always)
    private func coef(_ sec: Float) -> Float { expf(-1 / (sr * max(0.001, sec))) }

    /// Recompute cached coefficients after a genre change.
    private func configure() {
        let pr = profile
        kickAmpC = coef(pr.kickDecay); kickPitchC = coef(pr.kickPitchDecay)
        snareNC = coef(pr.snareDecay); snareTC = coef(pr.snareDecay * 0.6)
        hatC = coef(pr.hatDecay); openC = coef(pr.openDecay)
        percC = coef(pr.percDecay); percPitchC = coef(0.04)
        crashC = coef(1.2)
        bass.setup(wave: pr.bassWave, cutoff: pr.bassCutoff, cutoffAmt: pr.bassCutoffAmt,
                   cutoffDecay: pr.bassCutoffDecay, decay: pr.bassDecay, detune: pr.bassDetune,
                   sub: pr.bassSub, glideSec: pr.bassGlide, sr: sr)
        lead.setup(wave: pr.leadWave, cutoff: pr.leadCutoff, cutoffAmt: pr.leadCutoffAmt,
                   cutoffDecay: pr.leadCutoffDecay, decay: pr.leadDecay, detune: pr.leadDetune,
                   sub: 0, glideSec: 0.03, sr: sr)
        arp.setup(wave: pr.arpWave, cutoff: pr.arpCutoff, cutoffAmt: pr.arpCutoffAmt,
                  cutoffDecay: 0.08, decay: pr.arpDecay, detune: 0.004, sub: 0, glideSec: 0, sr: sr)
        for v in plucks {
            v.setup(wave: pr.arpWave, cutoff: pr.arpCutoff, cutoffAmt: pr.arpCutoffAmt * 1.2,
                    cutoffDecay: 0.1, decay: max(0.15, pr.arpDecay * 1.6), detune: 0.005, sub: 0,
                    glideSec: 0, sr: sr)
        }
        lastKey = -1   // force chord recalculation
    }

    private func recalcChord() {
        let ch = HarmonyEngine.chord(degree: degree, root: p.keyRoot, octave: 3, scaleIndex: p.scaleIndex)
        chordMidi[0] = ch.0; chordMidi[1] = ch.1; chordMidi[2] = ch.2; chordMidi[3] = ch.3
        for k in 0..<4 {
            padTarget[k] = HarmonyEngine.hz(chordMidi[k])
            if padFreq[k] == 0 { padFreq[k] = padTarget[k] }
        }
    }

    // MARK: Sequencer

    private func fireStep(_ s: Int, _ b: Int) {
        let seed = p.seed
        let ub = UInt32(truncatingIfNeeded: b)
        let us = UInt32(s)

        if s == 0 {
            let per = max(1, profile.barsPerChord)
            if b % per == 0 {
                let idx = b / per
                let progs = profile.progressions
                let variant = Int(hash32(seed, UInt32(truncatingIfNeeded: idx / 4), 77) % UInt32(progs.count))
                let seq = progs[variant]
                degree = seq[idx % seq.count]
                recalcChord()
            }
            if crashPending { crashEnv = 1; crashPending = false }
        }
        if p.keyRoot != lastKey || p.scaleIndex != lastScale {
            lastKey = p.keyRoot; lastScale = p.scaleIndex
            recalcChord()
        }
        if s % 4 == 0 { quarterCount &+= 1 }

        if p.fillCounter != lastFill { lastFill = p.fillCounter; fillArmed = true }
        if p.riserCounter != lastRiser {
            lastRiser = p.riserCounter
            riserLen = max(1, Int(Double(sr) * 60.0 / p.bpm * 4.0))
            riserLeft = riserLen
        }
        fillActive = fillArmed && s >= 8

        for l in 0..<8 {
            let enabled = (p.layerMask >> UInt8(l)) & 1 == 1
            var on = enabled && p.energy >= profile.thresholds[l]
            if l == 1 && fillActive && enabled { on = true }
            layerTarget[l] = on ? 1 : 0
        }

        let accent: Float = (s % 4 == 0) ? 1.0 : ((s % 2 == 0) ? 0.85 : 0.68)
        let jit = (hash01(seed, ub, us + 900) - 0.5) * p.humanize * 0.35
        let vel = min(1.1, max(0.3, accent + jit))
        let stepSamples = Float(60.0 / max(20.0, p.bpm) / 4.0) * sr
        let rnd = profile.randomized
        let cx = p.complexity, dn = p.density

        // Kick
        if layerTarget[0] > 0.5 {
            let pr = RhythmEngine.probability(profile.kick, kind: 0, randomized: rnd, step: s, bar: b, seed: seed)
            if RhythmEngine.hit(pr, salt: 0, step: s, bar: b, seed: seed, complexity: cx, density: dn) {
                kickEnv = max(0.6, vel); kickPitch = 1; kickPhase = 0
                kickCount &+= 1
            }
        }

        // Snare / clap, with pause fills
        if fillActive && layerTarget[1] > 0.5 {
            if s >= 12 || s % 2 == 0 {
                snareEnvN = 1; snareEnvT = 1; snareVel = 0.35 + 0.65 * Float(s - 8) / 7
            }
        } else if layerTarget[1] > 0.5 {
            let pr = RhythmEngine.probability(profile.snare, kind: 1, randomized: rnd, step: s, bar: b, seed: seed)
            if RhythmEngine.hit(pr, salt: 1, step: s, bar: b, seed: seed, complexity: cx, density: dn) {
                snareEnvN = 1; snareEnvT = 1; snareVel = pr >= 0.99 ? 1 : 0.6
            }
        }
        if fillActive && s == 15 { fillArmed = false; crashPending = true }

        // Hats
        if layerTarget[2] > 0.5 {
            let po = RhythmEngine.probability(profile.openHat, kind: 3, randomized: rnd, step: s, bar: b, seed: seed)
            if RhythmEngine.hit(po, salt: 3, step: s, bar: b, seed: seed, complexity: cx, density: dn) {
                openEnv = vel; hatEnv = 0
            } else {
                let ph = RhythmEngine.probability(profile.hat, kind: 2, randomized: rnd, step: s, bar: b, seed: seed)
                if RhythmEngine.hit(ph, salt: 2, step: s, bar: b, seed: seed, complexity: cx, density: dn) {
                    hatEnv = vel * 0.8; openEnv *= 0.2
                }
            }
        }

        // Percussion (FM blips tuned to the scale)
        if layerTarget[3] > 0.5 {
            let pp = RhythmEngine.probability(profile.perc, kind: 4, randomized: rnd, step: s, bar: b, seed: seed)
            if RhythmEngine.hit(pp, salt: 4, step: s, bar: b, seed: seed, complexity: cx, density: dn) {
                let pick = Int(hash32(seed, ub, us + 4400) % 4)
                let offs = pick == 0 ? 0 : (pick == 1 ? 2 : (pick == 2 ? 4 : 7))
                let m = HarmonyEngine.scaleNote(step: degree + offs, root: p.keyRoot,
                                                octave: profile.percOctave, scaleIndex: p.scaleIndex)
                percF1 = HarmonyEngine.hz(m)
                percF0 = percF1 * profile.percPitchMul
                percEnv = vel; percVel = 0.7; percPitch = 1; percPhase = 0; percMod = 0
            }
        }

        // Bass
        if layerTarget[4] > 0.5 {
            let pb = RhythmEngine.probability(profile.bass, kind: 5, randomized: rnd, step: s, bar: b, seed: seed)
            if RhythmEngine.hit(pb, salt: 5, step: s, bar: b, seed: seed, complexity: cx, density: dn) {
                let choice = hash01(seed, ub, us * 16 + 9)
                var off = 0
                if choice < profile.bassVariety {
                    off = choice < profile.bassVariety * 0.5 ? HarmonyEngine.scaleCount(p.scaleIndex) : 4
                }
                let m = HarmonyEngine.scaleNote(step: degree + off, root: p.keyRoot,
                                                octave: profile.bassOctave, scaleIndex: p.scaleIndex)
                bass.trigger(freq: HarmonyEngine.hz(m), vel: vel,
                             holdSamples: Int(profile.bassHoldSteps * stepSamples))
            }
        }

        // Arpeggiator (stateless: note = f(global step))
        if layerTarget[7] > 0.5 && s % max(1, profile.arpDiv) == 0 {
            let gs = b * 16 + s
            let n = gs / max(1, profile.arpDiv)
            let idx = SynthCore.arpOrder[n % 8]
            let octUp = (n / 8) % 2 == 1 ? 12 : 0
            if hash01(seed, UInt32(truncatingIfNeeded: gs), 5150) < 0.9 {
                arp.trigger(freq: HarmonyEngine.hz(chordMidi[idx] + 12 * profile.arpOctave + octUp),
                            vel: 0.5 + 0.3 * accent, holdSamples: 0)
            }
        }

        // Generative lead (stateless melody)
        if layerTarget[6] > 0.5 && s % 2 == 0 {
            let r = hash01(seed, ub, us * 16 + 11)
            if r < profile.leadProb * (0.5 + cx) {
                let off = SynthCore.leadOffsets[Int(hash32(seed, ub, us * 16 + 12) % 8)]
                let m = HarmonyEngine.scaleNote(step: degree + off, root: p.keyRoot,
                                                octave: profile.leadOctave, scaleIndex: p.scaleIndex)
                lead.trigger(freq: HarmonyEngine.hz(m), vel: 0.6 + 0.3 * accent,
                             holdSamples: Int(1.5 * stepSamples))
            }
        }

        // Typed-key plucks, quantized to this 16th step and snapped to the current scale.
        if p.keyHits != lastKeyHits {
            if (p.layerMask & Layer.lead.bit) != 0 {
                let n = min(2, Int(p.keyHits &- lastKeyHits))
                for k in 0..<n {
                    let h = hash32(seed, p.keyHits &+ UInt32(k), 4242)
                    let off = SynthCore.leadOffsets[Int(h % 8)]
                    let oct = (h >> 8) % 4 == 0 ? 5 : 4
                    let m = HarmonyEngine.scaleNote(step: degree + off, root: p.keyRoot,
                                                    octave: oct, scaleIndex: p.scaleIndex)
                    plucks[pluckRR].trigger(freq: HarmonyEngine.hz(m), vel: 0.7, holdSamples: 0)
                    pluckRR = (pluckRR + 1) % 4
                }
            }
            lastKeyHits = p.keyHits
        }
    }

    // MARK: Render

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if shared.pull(into: &p, profile: &profile, seen: &seenVersion) { configure() }
        let twoPi = 2 * Float.pi

        for i in 0..<frames {
            let rt: Float = p.playing ? 1 : 0
            runGain += (rt - runGain) * 0.002
            if !p.playing && runGain < 0.0005 { left[i] = 0; right[i] = 0; continue }

            while sched.samplesToNext <= 0 {
                fireStep(sched.step, sched.bar)
                sched.consume(bpm: p.bpm, swing: Double(p.swing), sampleRate: Double(sr))
            }
            sched.samplesToNext -= 1

            for l in 0..<8 { layerGain[l] += (layerTarget[l] - layerGain[l]) * layerSlew }

            // Kick
            var kickOut: Float = 0
            if kickEnv > 0.0005 {
                let f = profile.kickF1 + (profile.kickF0 - profile.kickF1) * kickPitch
                kickPhase += f * invSr; if kickPhase >= 1 { kickPhase -= 1 }
                var s = sinf(twoPi * kickPhase)
                s += profile.kickClick * kickPitch * kickPitch * kickPitch * noise()
                kickOut = tanhf(s * kickEnv * profile.kickDrive) * 0.9
                kickEnv *= kickAmpC; kickPitch *= kickPitchC
            }

            // Snare
            var snareOut: Float = 0
            if snareEnvN > 0.0005 || snareEnvT > 0.0005 {
                snarePhase += profile.snareFreq * invSr; if snarePhase >= 1 { snarePhase -= 1 }
                let n = noise()
                snareLP += 0.25 * (n - snareLP)
                let hp = n - snareLP
                snareOut = (hp * snareEnvN * profile.snareNoise
                            + sinf(twoPi * snarePhase) * snareEnvT * profile.snareTone) * snareVel
                snareEnvN *= snareNC; snareEnvT *= snareTC
            }

            // Hats
            var hatOut: Float = 0
            if hatEnv > 0.0005 || openEnv > 0.0005 {
                let n = noise()
                hatLP += 0.6 * (n - hatLP)
                hatOut = (n - hatLP) * (hatEnv * 0.5 + openEnv * 0.45)
                hatEnv *= hatC; openEnv *= openC
            }

            // Perc
            var percOut: Float = 0
            if percEnv > 0.0005 {
                let f = percF1 + (percF0 - percF1) * percPitch
                percPhase += f * invSr; if percPhase >= 1 { percPhase -= 1 }
                percMod += f * profile.fmRatio * invSr; if percMod >= 1 { percMod -= 1 }
                let m = sinf(twoPi * percMod) * profile.fmIndex * percEnv
                percOut = sinf(twoPi * (percPhase + m)) * percEnv * percVel
                percEnv *= percC; percPitch *= percPitchC
            }

            // Crash + riser
            var fxOut: Float = 0
            if crashEnv > 0.0005 {
                let n = noise()
                crashLP += 0.35 * (n - crashLP)
                fxOut += (n - crashLP) * crashEnv * 0.35
                crashEnv *= crashC
            }
            if riserLeft > 0 {
                let t = 1 - Float(riserLeft) / Float(riserLen)
                let n = noise()
                riserLP += (0.03 + 0.5 * t * t) * (n - riserLP)
                fxOut += (n - riserLP) * t * t * 0.3
                riserLeft -= 1
            }

            // Synth voices
            let bassOut = bass.next(sr: sr, invSr: invSr)
            let leadOut = lead.next(sr: sr, invSr: invSr)
            let arpOut = arp.next(sr: sr, invSr: invSr)
            var pluckOut: Float = 0
            for v in plucks { pluckOut += v.next(sr: sr, invSr: invSr) }

            // Pad
            padLFO += 0.13 * invSr; if padLFO >= 1 { padLFO -= 1 }
            let lfo = 0.5 + 0.5 * sinf(twoPi * padLFO)
            let padCut = profile.padCutoff * (0.55 + 0.7 * lfo + 0.8 * p.atmosphere)
            let pa = 1 - expf(-twoPi * min(padCut, 0.45 * sr) * invSr)
            var padL: Float = 0, padR: Float = 0
            for k in 0..<4 {
                padFreq[k] += (padTarget[k] - padFreq[k]) * padGlide
                let f = padFreq[k]
                padPhA[k] += f * invSr; if padPhA[k] >= 1 { padPhA[k] -= 1 }
                padPhB[k] += f * (1 + profile.padDetune) * invSr; if padPhB[k] >= 1 { padPhB[k] -= 1 }
                padL += 2 * padPhA[k] - 1
                padR += 2 * padPhB[k] - 1
            }
            padL1 += pa * (padL * 0.25 - padL1); padL2 += pa * (padL1 - padL2)
            padR1 += pa * (padR * 0.25 - padR1); padR2 += pa * (padR1 - padR2)

            // Mix
            let g = layerGain
            let lv = profile.levels
            let duck = 1 - 0.45 * min(1, kickEnv) * g[0]
            let drums = kickOut * g[0] * lv[0] + snareOut * g[1] * lv[1]
            let hatMix = hatOut * g[2] * lv[2]
            let percMix = percOut * g[3] * lv[3]
            let bassMix = bassOut * g[4] * lv[4] * duck
            let padGain = g[5] * lv[5] * (0.6 + 0.6 * p.atmosphere) * duck
            let padMixL = padL2 * padGain, padMixR = padR2 * padGain
            let pluckMix = pluckOut * 0.55 * lv[6]
            let leadMix = leadOut * g[6] * lv[6] + pluckMix
            let arpMix = arpOut * g[7] * lv[7]

            // Sends
            let dTarget = min(Float(60.0 / max(20.0, p.bpm)) * profile.delayBeats * sr, Float(delaySize - 4))
            delaySamples += (dTarget - delaySamples) * 0.0003
            var rp = Float(delayWrite) - delaySamples
            if rp < 0 { rp += Float(delaySize) }
            let i0 = Int(rp) % delaySize
            let fr = rp - Float(Int(rp))
            let i1 = (i0 + 1) % delaySize
            let dL = delayL[i0] * (1 - fr) + delayL[i1] * fr
            let dR = delayR[i0] * (1 - fr) + delayR[i1] * fr
            let dIn = (leadMix + arpMix) * profile.delaySend
            delayL[delayWrite] = dIn + dR * profile.delayFeedback
            delayR[delayWrite] = dL * profile.delayFeedback
            delayWrite += 1; if delayWrite == delaySize { delayWrite = 0 }

            let rIn = ((padMixL + padMixR) * 0.25 + leadMix * 0.5 + arpMix * 0.3 + snareOut * g[1] * 0.4)
                      * (profile.reverbSend + 0.3 * p.atmosphere)
            let (revL, revR) = reverb.process(rIn, feedback: profile.reverbFeedback)

            var l = drums + hatMix * 0.85 + percMix * 0.8 + bassMix + padMixL + leadMix
                  + arpMix * 0.9 + dL * 0.8 + revL + fxOut
            var r = drums + hatMix * 1.15 + percMix * 1.2 + bassMix + padMixR + leadMix
                  + arpMix * 1.1 + dR * 0.8 + revR + fxOut
            l *= 0.55; r *= 0.55

            // Anti-clipping: fast-attack limiter followed by a soft clipper.
            let peak = max(abs(l), abs(r))
            limEnv = peak > limEnv ? peak : limEnv + (peak - limEnv) * 0.0004
            if limEnv > 0.9 { let gn = 0.9 / limEnv; l *= gn; r *= gn }
            left[i] = softClip(l) * runGain
            right[i] = softClip(r) * runGain

            // Meters
            mDrums = max(mDrums * 0.9996, abs(drums) + abs(hatMix) * 0.5 + abs(percMix) * 0.5)
            mBass = max(mBass * 0.9996, abs(bassMix))
            mMelody = max(mMelody * 0.9996, abs(leadMix) + abs(arpMix) + abs(padMixL) * 0.5)
        }
    }
}
