import SwiftUI

// All three visualizers read `AudioAnalyzer.snapshot()`, i.e. the real post-mix output signal.

struct WaveformVisualizer: View {
    let analyzer: AudioAnalyzer

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let snap = analyzer.snapshot()
                let wave = snap.waveform
                guard wave.count > 8, size.width > 10 else { return }
                let w = size.width, h = size.height, mid = h / 2

                // Grid
                var grid = Path()
                for i in 1..<8 {
                    let x = w * CGFloat(i) / 8
                    grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h))
                }
                grid.move(to: CGPoint(x: 0, y: mid)); grid.addLine(to: CGPoint(x: w, y: mid))
                ctx.stroke(grid, with: .color(.white.opacity(0.05)), lineWidth: 1)

                // Envelope (min/max per column)
                let cols = max(64, Int(w / 3))
                let per = max(1, wave.count / cols)
                var upper: [CGPoint] = [], lower: [CGPoint] = [], center: [CGPoint] = []
                let gain: CGFloat = 0.92
                for c in 0..<cols {
                    let s0 = c * per
                    let s1 = min(s0 + per, wave.count)
                    if s0 >= s1 { break }
                    var mn: Float = 1, mx: Float = -1, sum: Float = 0
                    for k in s0..<s1 { mn = min(mn, wave[k]); mx = max(mx, wave[k]); sum += wave[k] }
                    let x = w * CGFloat(c) / CGFloat(cols - 1)
                    upper.append(CGPoint(x: x, y: mid - CGFloat(mx) * mid * gain))
                    lower.append(CGPoint(x: x, y: mid - CGFloat(mn) * mid * gain))
                    center.append(CGPoint(x: x, y: mid - CGFloat(sum / Float(s1 - s0)) * mid * gain))
                }
                guard upper.count > 2 else { return }

                var shape = Path()
                shape.move(to: upper[0])
                for p in upper.dropFirst() { shape.addLine(to: p) }
                for p in lower.reversed() { shape.addLine(to: p) }
                shape.closeSubpath()
                ctx.fill(shape, with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.5), Theme.cyan.opacity(0.35)]),
                    startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))

                var line = Path()
                line.move(to: center[0])
                for p in center.dropFirst() { line.addLine(to: p) }
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 5))
                    l.stroke(line, with: .color(Theme.accent.opacity(0.8)), lineWidth: 2.5)
                }
                ctx.stroke(line, with: .color(Theme.accent), lineWidth: 1.2)

                // RMS guides
                let r = CGFloat(snap.rms) * mid * gain
                var guide = Path()
                guide.move(to: CGPoint(x: 0, y: mid - r)); guide.addLine(to: CGPoint(x: w, y: mid - r))
                guide.move(to: CGPoint(x: 0, y: mid + r)); guide.addLine(to: CGPoint(x: w, y: mid + r))
                ctx.stroke(guide, with: .color(Theme.cyan.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
            }
        }
    }
}

final class PeakHolder {
    var peaks = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
    func update(_ bands: [Float]) {
        for i in 0..<min(peaks.count, bands.count) {
            peaks[i] = max(bands[i], peaks[i] - 0.008)
        }
    }
}

struct SpectrumVisualizer: View {
    let analyzer: AudioAnalyzer
    @State private var holder = PeakHolder()

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation) { _ in
                Canvas { ctx, size in
                    let snap = analyzer.snapshot()
                    guard !snap.bands.isEmpty else { return }
                    holder.update(snap.bands)
                    let n = snap.bands.count
                    let slot = size.width / CGFloat(n)
                    let barW = slot * 0.68
                    for i in 0..<n {
                        let v = CGFloat(snap.bands[i])
                        let bh = max(2, v * size.height * 0.95)
                        let x = CGFloat(i) * slot + (slot - barW) / 2
                        let rect = CGRect(x: x, y: size.height - bh, width: barW, height: bh)
                        let t = Double(i) / Double(n)
                        let col = Theme.mix(t)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                                 with: .linearGradient(Gradient(colors: [col, col.opacity(0.25)]),
                                                       startPoint: CGPoint(x: x, y: size.height - bh),
                                                       endPoint: CGPoint(x: x, y: size.height)))
                        let py = size.height - CGFloat(holder.peaks[i]) * size.height * 0.95
                        ctx.fill(Path(CGRect(x: x, y: py - 3, width: barW, height: 2)),
                                 with: .color(Theme.cyan.opacity(0.9)))
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let s = analyzer.snapshot()
                HStack {
                    BandLabel(name: "BASS", value: s.bass)
                    Spacer()
                    BandLabel(name: "MID", value: s.mid)
                    Spacer()
                    BandLabel(name: "TREBLE", value: s.treble)
                }
            }
        }
    }
}

private struct BandLabel: View {
    let name: String
    let value: Float
    var body: some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(Theme.dim)
            Capsule().fill(Color.white.opacity(0.08)).frame(width: 60, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.accent).frame(width: 60 * CGFloat(min(1, value * 1.3)), height: 4)
                }
        }
    }
}

final class PulseState {
    struct Particle { var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, life: CGFloat, cyan: Bool }
    struct Ring { var r: CGFloat, a: CGFloat }
    var particles: [Particle] = []
    var rings: [Ring] = []
    var lastKick: UInt32 = 0
    var lastQuarter: UInt32 = 0
    var rotation: CGFloat = 0
    var kickFlash: CGFloat = 0
    var beatFlash: CGFloat = 0
    var radius: CGFloat = 0
    var lastTime: TimeInterval = 0

    func update(now: TimeInterval, meters: SynthMeters, snap: AudioAnalyzer.Snapshot,
                size: CGSize, emit: Bool) {
        let dt = CGFloat(min(0.05, lastTime == 0 ? 0.016 : now - lastTime))
        lastTime = now
        let base = min(size.width, size.height) * 0.2
        rotation += dt * (0.15 + CGFloat(snap.mid) * 0.8)
        kickFlash *= 0.90
        beatFlash *= 0.92
        let target = base * (1 + CGFloat(snap.bass) * 0.35 + CGFloat(snap.rms) * 1.2)
        radius += (target - radius) * 0.3

        if meters.kickCount != lastKick {
            lastKick = meters.kickCount
            kickFlash = 1
            rings.append(Ring(r: radius, a: 0.9))
            if emit {
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for k in 0..<14 {
                    let ang = CGFloat(k) / 14 * .pi * 2 + rotation
                    let sp = CGFloat.random(in: 60...180)
                    particles.append(Particle(x: c.x + cos(ang) * radius, y: c.y + sin(ang) * radius,
                                              vx: cos(ang) * sp, vy: sin(ang) * sp, life: 1, cyan: k % 3 == 0))
                }
            }
        }
        if meters.quarterCount != lastQuarter { lastQuarter = meters.quarterCount; beatFlash = 1 }

        for i in rings.indices { rings[i].r += dt * 260; rings[i].a -= dt * 1.1 }
        rings.removeAll { $0.a <= 0 }
        for i in particles.indices {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vx *= 0.985; particles[i].vy *= 0.985
            particles[i].life -= dt * 0.9
        }
        particles.removeAll { $0.life <= 0 }
        if particles.count > 400 { particles.removeFirst(particles.count - 400) }
    }
}

struct PulseVisualizer: View {
    let analyzer: AudioAnalyzer
    let meters: () -> SynthMeters
    let particlesEnabled: Bool
    @State private var state = PulseState()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let snap = analyzer.snapshot()
                state.update(now: tl.date.timeIntervalSinceReferenceDate, meters: meters(),
                             snap: snap, size: size, emit: particlesEnabled)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = state.radius

                for ring in state.rings {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ring.r, y: c.y - ring.r,
                                                      width: ring.r * 2, height: ring.r * 2)),
                               with: .color(Theme.cyan.opacity(Double(max(0, ring.a)) * 0.6)), lineWidth: 1.5)
                }

                // Spectrum-reactive polygon (mirrored)
                let bands = snap.bands
                let pts = 96
                var poly = Path()
                for i in 0..<pts {
                    let t = CGFloat(i) / CGFloat(pts)
                    let m = t < 0.5 ? t * 2 : (1 - t) * 2
                    let bi = min(bands.isEmpty ? 0 : bands.count - 1, Int(m * CGFloat(max(1, bands.count - 1))))
                    let v = bands.isEmpty ? 0 : CGFloat(bands[bi])
                    let ang = t * .pi * 2 + state.rotation
                    let rr = R * (1.15 + v * 0.55)
                    let p = CGPoint(x: c.x + cos(ang) * rr, y: c.y + sin(ang) * rr)
                    if i == 0 { poly.move(to: p) } else { poly.addLine(to: p) }
                }
                poly.closeSubpath()
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 8))
                    l.stroke(poly, with: .color(Theme.accent.opacity(0.7)), lineWidth: 3)
                }
                ctx.stroke(poly, with: .color(Theme.accent), lineWidth: 1.4)

                // Core
                let core = R * (0.62 + 0.18 * state.kickFlash)
                let coreRect = CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)
                ctx.fill(Path(ellipseIn: coreRect),
                         with: .radialGradient(Gradient(colors: [Theme.accent.opacity(0.55 + 0.4 * Double(state.kickFlash)),
                                                                 Theme.cyan.opacity(0.05)]),
                                               center: c, startRadius: 0, endRadius: core))
                ctx.stroke(Path(ellipseIn: coreRect), with: .color(Theme.cyan.opacity(0.4 + 0.5 * Double(state.beatFlash))),
                           lineWidth: 1.5)

                // Geometric inner triangle, beat-synchronized
                var tri = Path()
                for k in 0..<3 {
                    let ang = -state.rotation * 2 + CGFloat(k) * .pi * 2 / 3
                    let p = CGPoint(x: c.x + cos(ang) * core * 0.7, y: c.y + sin(ang) * core * 0.7)
                    if k == 0 { tri.move(to: p) } else { tri.addLine(to: p) }
                }
                tri.closeSubpath()
                ctx.stroke(tri, with: .color(.white.opacity(0.25 + 0.5 * Double(state.beatFlash))), lineWidth: 1)

                for p in state.particles {
                    let r: CGFloat = 1.5 + 1.5 * p.life
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color((p.cyan ? Theme.cyan : Theme.accent).opacity(Double(max(0, p.life)))))
                }
            }
        }
    }
}
