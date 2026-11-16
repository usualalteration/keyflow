import SwiftUI

struct VerticalGainSlider: View {
    @Binding var value: Double      // dB, -12...+12
    private let r: CGFloat = 7

    var body: some View {
        GeometryReader { g in
            let h = max(1, g.size.height)
            let frac = CGFloat((value + 12) / 24)
            let y = r + (1 - frac) * (h - 2 * r)
            let mid = h / 2
            let cx = g.size.width / 2
            ZStack {
                Capsule().fill(Color.white.opacity(0.08)).frame(width: 4, height: h).position(x: cx, y: mid)
                Rectangle().fill(Theme.accent.opacity(0.55))
                    .frame(width: 4, height: max(0.5, abs(y - mid))).position(x: cx, y: (y + mid) / 2)
                Rectangle().fill(Color.white.opacity(0.28)).frame(width: 16, height: 1).position(x: cx, y: mid)
                Circle().fill(Theme.accent).frame(width: r * 2, height: r * 2)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 4).position(x: cx, y: y)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = 1 - min(1, max(0, (v.location.y - r) / (h - 2 * r)))
                var db = Double(f) * 24 - 12
                if abs(db) < 0.6 { db = 0 }
                value = (db * 2).rounded() / 2
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
    }
}

struct EqualizerView: View {
    @EnvironmentObject var settings: SettingsManager

    static let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let presets: [(String, [Double])] = [
        ("Flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Bass boost", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        ("Warm", [3, 3, 2, 1, 0, 0, -1, -2, -3, -4]),
        ("Bright", [-2, -1, 0, 0, 0, 1, 2, 4, 5, 6]),
        ("V-shape", [5, 4, 2, 0, -2, -2, 0, 2, 4, 5]),
        ("Lo-fi", [-9, -6, -2, 2, 3, 3, 0, -4, -8, -12])
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Spacer()
                Toggle("EQ", isOn: $settings.config.eqEnabled)
                    .toggleStyle(.switch).tint(Theme.accent)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Menu("Presets") {
                    ForEach(EqualizerView.presets, id: \.0) { preset in
                        Button(preset.0) { settings.config.eqGains = preset.1 }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                Button("Reset") { settings.config.eqGains = Array(repeating: 0, count: 10) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.cyan)
            }
            .padding(.top, 10).padding(.trailing, 14)

            ZStack {
                curve
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        VStack(spacing: 4) {
                            Text(String(format: "%+.1f", settings.config.eqGains[i]))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(settings.config.eqGains[i] == 0 ? Theme.dim : Theme.accent)
                                .frame(height: 16)
                            VerticalGainSlider(value: gainBinding(i))
                            Text(EqualizerView.labels[i])
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.dim)
                                .frame(height: 16)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 14)
            .opacity(settings.config.eqEnabled ? 1 : 0.4)
        }
    }

    private func gainBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { settings.config.eqGains[i] },
                set: { v in
                    var g = settings.config.eqGains
                    g[i] = v
                    settings.config.eqGains = g
                })
    }

    /// Response curve through the knob positions (decorative, mirrors the slider travel).
    private var curve: some View {
        Canvas { ctx, size in
            let n = 10
            let r: CGFloat = 7
            let h = size.height - 40
            func pt(_ i: Int) -> CGPoint {
                let frac = CGFloat((settings.config.eqGains[i] + 12) / 24)
                return CGPoint(x: size.width * (CGFloat(i) + 0.5) / CGFloat(n),
                               y: 20 + r + (1 - frac) * (h - 2 * r))
            }
            var path = Path()
            path.move(to: pt(0))
            for i in 1..<n {
                let a = pt(i - 1), b = pt(i)
                let mx = (a.x + b.x) / 2
                path.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 6))
                l.stroke(path, with: .color(Theme.accent.opacity(0.6)), lineWidth: 3)
            }
            ctx.stroke(path, with: .color(Theme.mix(0.2).opacity(0.9)), lineWidth: 1.4)
        }
        .allowsHitTesting(false)
    }
}
