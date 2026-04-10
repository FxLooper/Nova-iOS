import Foundation
import Accelerate

// MARK: - AudioLivenessDetector
// Premium anti-spoofing pro Voice ID.
//
// Detekuje 3 typy útoků:
//   1. Replay attack — přehrání nahraného hlasu (z rekordéru, telefonu)
//   2. TTS synthesis attack — syntetický hlas (Apple TTS, Google TTS)
//   3. Static / silence — žádný reálný hlas
//
// Použité techniky (klasické signal processing, žádné ML):
//   - Spectral flatness (Wiener entropy) — odlišení šumu od harmonického signálu
//   - Energy variance — reálná řeč má dynamiku, replay je často "flat"
//   - Zero-crossing rate — kvantitativní míra harmoničnosti
//   - RMS distribution — má příliš uniformní = pravděpodobně replay
//
// Použití:
//   let detector = AudioLivenessDetector()
//   let result = detector.analyze(samples: floatArray, sampleRate: 16000)
//   if !result.isLive {
//     // Reject — voice ID neproběhne
//   }

struct LivenessResult {
    let isLive: Bool
    let confidence: Float  // 0.0 (definitely spoofed) - 1.0 (definitely live)
    let reason: String?    // Human-readable důvod při fail

    // Detailed metrics
    let spectralFlatness: Float
    let energyVariance: Float
    let zeroCrossingRate: Float
    let rmsCV: Float  // coefficient of variation
}

@MainActor
class AudioLivenessDetector {

    // Thresholds (kalibrované empiricky)
    // Real human speech: spectral flatness obvykle 0.05-0.25
    // TTS synthesis: často <0.05 (too clean) nebo >0.4 (too noisy)
    // Replay: 0.10-0.30 (similar to live, ale s méně variancí)

    private let minSpectralFlatness: Float = 0.02   // pod = TTS / silence
    private let maxSpectralFlatness: Float = 0.45   // nad = noise / fake
    private let minEnergyVariance: Float = 0.001    // pod = static / replay
    private let minRMSCoefficient: Float = 0.15     // pod = příliš uniformní

    /// Analyze audio buffer for liveness.
    /// - Parameter samples: 16kHz mono Float32 [-1.0, 1.0]
    /// - Parameter sampleRate: Sample rate (default 16000)
    /// - Returns: Liveness result with confidence and reason
    func analyze(samples: [Float], sampleRate: Float = 16000) -> LivenessResult {
        guard samples.count >= Int(sampleRate) else {
            return LivenessResult(
                isLive: false,
                confidence: 0,
                reason: "Audio too short (need ≥1s)",
                spectralFlatness: 0, energyVariance: 0, zeroCrossingRate: 0, rmsCV: 0
            )
        }

        // 1. Spectral flatness (Wiener entropy)
        let flatness = computeSpectralFlatness(samples: samples)

        // 2. Energy variance — segment audio do 10 chunks, compute RMS na každém
        let chunkCount = 10
        let chunkSize = samples.count / chunkCount
        var rmsValues = [Float]()
        for i in 0..<chunkCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            let chunk = Array(samples[start..<end])
            rmsValues.append(computeRMS(chunk))
        }
        let energyVariance = computeVariance(rmsValues)
        let rmsMean = rmsValues.reduce(0, +) / Float(rmsValues.count)
        let rmsCV = rmsMean > 0 ? sqrt(energyVariance) / rmsMean : 0

        // 3. Zero-crossing rate
        let zcr = computeZeroCrossingRate(samples: samples)

        // 4. Decision logic
        var failures: [String] = []

        if flatness < minSpectralFlatness {
            failures.append("Audio příliš čisté (TTS/synthesized?)")
        }
        if flatness > maxSpectralFlatness {
            failures.append("Audio příliš šumové (noise?)")
        }
        if energyVariance < minEnergyVariance {
            failures.append("Audio bez dynamiky (replay/static?)")
        }
        if rmsCV < minRMSCoefficient {
            failures.append("Příliš uniformní hlasitost (replay?)")
        }

        // Compute confidence — vážený průměr metrik v "good" rozsahu
        let flatnessScore = flatness >= minSpectralFlatness && flatness <= maxSpectralFlatness ? 1.0 : 0.0
        let varianceScore = energyVariance >= minEnergyVariance ? 1.0 : 0.0
        let cvScore = rmsCV >= minRMSCoefficient ? 1.0 : 0.0
        let confidence = Float((flatnessScore + varianceScore + cvScore) / 3.0)

        let isLive = failures.isEmpty
        let reason = failures.isEmpty ? nil : failures.joined(separator: ", ")

        return LivenessResult(
            isLive: isLive,
            confidence: confidence,
            reason: reason,
            spectralFlatness: flatness,
            energyVariance: energyVariance,
            zeroCrossingRate: zcr,
            rmsCV: rmsCV
        )
    }

    // MARK: - Signal processing helpers

    /// Spectral flatness (Wiener entropy) — geometrický průměr / aritmetický průměr power spektra.
    /// 0 = pure tone, 1 = white noise. Speech ~0.05-0.25.
    private func computeSpectralFlatness(samples: [Float]) -> Float {
        // Použijeme malé okno (1024 samples) s overlapping
        let windowSize = 1024
        guard samples.count >= windowSize else { return 0 }

        // Vezmeme střední část audia (vyhneme se začátku/konci silence)
        let midStart = (samples.count - windowSize) / 2
        let window = Array(samples[midStart..<midStart + windowSize])

        // FFT setup
        let log2n = vDSP_Length(log2(Float(windowSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realp = [Float](repeating: 0, count: windowSize / 2)
        var imagp = [Float](repeating: 0, count: windowSize / 2)
        var magnitudes = [Float](repeating: 0, count: windowSize / 2)

        let result = realp.withUnsafeMutableBufferPointer { realPtr -> Float in
            return imagp.withUnsafeMutableBufferPointer { imagPtr -> Float in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                window.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: windowSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(windowSize / 2))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(windowSize / 2))

                // Compute spectral flatness = exp(mean(log(power))) / mean(power)
                // Skip DC (index 0)
                let validMags = Array(magnitudes[1..<magnitudes.count]).map { max($0, 1e-10) }
                let logMean = validMags.map { log($0) }.reduce(0, +) / Float(validMags.count)
                let arithMean = validMags.reduce(0, +) / Float(validMags.count)

                guard arithMean > 0 else { return 0 }
                return exp(logMean) / arithMean
            }
        }

        return result
    }

    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var meanSq: Float = 0
        vDSP_measqv(samples, 1, &meanSq, vDSP_Length(samples.count))
        return sqrt(meanSq)
    }

    private func computeVariance(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return squaredDiffs.reduce(0, +) / Float(values.count - 1)
    }

    private func computeZeroCrossingRate(samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i - 1] >= 0) != (samples[i] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count)
    }
}
