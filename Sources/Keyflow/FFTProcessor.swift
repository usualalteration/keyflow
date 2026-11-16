import Foundation
import Accelerate

/// Real FFT (Hann window) built on Accelerate/vDSP.
final class FFTProcessor {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private(set) var magnitudes: [Float]

    init(size: Int) {
        self.size = size
        log2n = vDSP_Length(log2(Double(size)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
        magnitudes = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `input` must hold `size` samples. Result in `magnitudes` (amplitude-normalized).
    func process(_ input: UnsafePointer<Float>) {
        let half = size / 2
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(size))
        windowed.withUnsafeBufferPointer { wp in
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    magnitudes.withUnsafeMutableBufferPointer { mp in
                        vDSP_zvabs(&split, 1, mp.baseAddress!, 1, vDSP_Length(half))
                    }
                }
            }
        }
        let inv = 1 / Float(size)
        for i in 0..<half { magnitudes[i] *= inv }
    }
}
