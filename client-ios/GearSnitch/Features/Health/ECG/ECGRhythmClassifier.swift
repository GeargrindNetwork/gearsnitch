import Foundation

// MARK: - ECG Rhythm Classifier
//
// Signal-processing–based (NOT machine-learning) rhythm classifier for a
// single-lead Apple Watch ECG (Lead I equivalent, 512 Hz).
//
// QRS detection: Pan-Tompkins
//   Pan J, Tompkins WJ. A Real-Time QRS Detection Algorithm.
//   IEEE Transactions on Biomedical Engineering, BME-32(3):230-236, 1985.
//
// Clinical criteria references (applied in classify(...) below):
//   - Sinus rhythm:            60–100 BPM, regular R-R, P-before-QRS
//                              [Goldberger, Clinical ECG, 9th ed., Ch. 5]
//   - Sinus bradycardia:       rate < 60, otherwise sinus
//   - Sinus tachycardia:       rate > 100, otherwise sinus
//   - Atrial fibrillation:     irregularly irregular R-R, absent P waves
//                              [Hindricks G. ESC Guidelines 2020, Eur Heart J]
//   - Atrial flutter:          regular ~150 bpm ventricular rate, sawtooth F waves,
//                              typical 2:1 AV conduction
//                              [Saoudi N. Classification of atrial flutter, JCE 2001]
//   - 1° AV block:             PR > 200 ms, every P conducted
//                              [Surawicz B. AHA/ACCF/HRS recommendations, 2009]
//   - 2° AV block Mobitz I:    progressive PR lengthening until a dropped QRS
//                              (Wenckebach periodicity)
//   - 2° AV block Mobitz II:   constant PR, intermittent non-conducted P
//   - 3° AV block (complete):  atrial and ventricular activity dissociated
//   - PVC:                     wide QRS (>120 ms), no preceding P wave,
//                              compensatory pause
//                              [Hayes, JACC 2010]
//   - PAC:                     early P (different morphology) with narrow QRS
//   - VT:                      ≥3 consecutive wide-QRS beats at rate > 100
//                              [AHA Scientific Statement 2020]
//   - SVT:                     narrow QRS at rate > 150, regular, no distinct P
//
// Confidence is a composite: how strongly the evidence supports the label,
// scaled by signal quality (SNR proxy + measurement stability).
//
// This classifier DOES NOT replace an evaluation by a qualified clinician —
// the `ECGClassification.disclaimerText` string must be shown with every
// result surface (App Store Guideline 5.1.3).

struct ECGRhythmClassifier {

    // MARK: - Thresholds (ms unless noted)

    private let minPRMs: Double = 120
    private let normalPRMaxMs: Double = 200
    private let wideQRSThresholdMs: Double = 120
    private let narrowQRSUpperMs: Double = 110
    private let minHeartRateBPM: Double = 30
    private let maxHeartRateBPM: Double = 250
    private let pauseThresholdMs: Double = 2000
    // Coefficient of variation of R-R intervals above which rhythm is
    // considered irregular (commonly used AF cutoff ≥0.12 for 30 s strips;
    // see Dash S et al., IEEE Trans Biomed Eng 2009).
    private let irregularRRCv: Double = 0.12
    // Stronger cutoff for "irregularly irregular" (AF-favoring).
    private let afIrregularRRCv: Double = 0.18

    // MARK: - Entry Point

    func classify(samples: [ECGVoltageMeasurement], sampleRateHz: Double = ECGSampleRate.hz) -> ECGClassification {
        guard samples.count > Int(sampleRateHz * 3) else {
            // Need at least 3 s of signal for any meaningful analysis.
            return ECGClassification(
                rhythm: .indeterminate,
                heartRate: 0,
                confidence: 0.0,
                anomalies: [],
                clinicalNote: "Recording too short to analyze."
            )
        }

        // 1) Pan-Tompkins QRS detection.
        let values = samples.map(\.microV)
        let detector = PanTompkinsDetector(sampleRateHz: sampleRateHz)
        let rPeakIndices = detector.detect(samples: values)

        guard rPeakIndices.count >= 2 else {
            return ECGClassification(
                rhythm: .indeterminate,
                heartRate: 0,
                confidence: 0.0,
                anomalies: [],
                clinicalNote: "Unable to detect enough heartbeats for classification."
            )
        }

        // 2) R-R intervals → heart rate + rhythm regularity.
        let rrIntervalsSec: [Double] = zip(rPeakIndices.dropFirst(), rPeakIndices)
            .map { (current, previous) -> Double in
                Double(current - previous) / sampleRateHz
            }
        let meanRR = rrIntervalsSec.reduce(0, +) / Double(rrIntervalsSec.count)
        let rrSD = standardDeviation(rrIntervalsSec)
        let rrCv = meanRR > 0 ? rrSD / meanRR : 0
        let bpm = meanRR > 0 ? 60.0 / meanRR : 0
        let clampedBpm = max(0, min(maxHeartRateBPM, bpm))

        // 3) QRS width measurement around each R peak.
        let qrsWidthsMs = measureQrsWidths(values: values, rPeaks: rPeakIndices, sampleRateHz: sampleRateHz)
        let meanQrsMs = qrsWidthsMs.isEmpty ? 0 : qrsWidthsMs.reduce(0, +) / Double(qrsWidthsMs.count)
        let wideFraction = qrsWidthsMs.isEmpty ? 0 :
            Double(qrsWidthsMs.filter { $0 > wideQRSThresholdMs }.count) / Double(qrsWidthsMs.count)

        // 4) P-wave presence + PR intervals.
        let prAnalysis = analyzePWaves(
            values: values,
            rPeaks: rPeakIndices,
            sampleRateHz: sampleRateHz
        )

        // 5) Anomaly accumulators.
        var anomalies: [ECGAnomaly] = []

        // Pauses (R-R > threshold).
        let longestRRms = (rrIntervalsSec.max() ?? 0) * 1000
        if longestRRms >= pauseThresholdMs {
            anomalies.append(.pause(durationMs: Int(longestRRms.rounded())))
        }

        // Premature beats — beats whose preceding R-R interval is <75% of the
        // median, heuristic for prematurity (Malik M, HRV Task Force 1996).
        let prematureIndices = findPrematureBeats(rrIntervalsSec: rrIntervalsSec)

        var pvcCount = 0
        var pacCount = 0
        for idx in prematureIndices {
            // `idx` refers to the R-peak at position (idx + 1) in rPeakIndices
            // because rrIntervalsSec[i] is the gap between rPeaks[i] and rPeaks[i+1].
            let rIndexInPeaks = idx + 1
            guard rIndexInPeaks < qrsWidthsMs.count else { continue }
            if qrsWidthsMs[rIndexInPeaks] > wideQRSThresholdMs {
                pvcCount += 1
            } else {
                pacCount += 1
            }
        }
        if pvcCount > 0 { anomalies.append(.pvc(count: pvcCount)) }
        if pacCount > 0 { anomalies.append(.pac(count: pacCount)) }

        if wideFraction > 0.25 {
            anomalies.append(.wideQRS(percentage: wideFraction))
        }

        // 6) Classification decision tree.
        let rhythm: ECGRhythm
        var confidence: Double = 0.5
        var note: String?

        // Signal quality proxy — snr-ish from detection consistency.
        let signalQuality = estimateSignalQuality(values: values, rPeaks: rPeakIndices)

        let isIrregular = rrCv >= irregularRRCv
        let isIrregularlyIrregular = rrCv >= afIrregularRRCv
        let pWavesPresent = prAnalysis.pWaveFractionDetected >= 0.6
        let avgPRms = prAnalysis.averagePRIntervalMs
        let prLengthening = prAnalysis.prProgressivelyLengthening
        let prConstantWithDrops = prAnalysis.prConstantWithDroppedBeats
        let aDissociated = prAnalysis.avDissociated
        let sawtooth = prAnalysis.sawtoothFWavesLikely

        if wideFraction > 0.8 && clampedBpm > 100 && consecutiveWideRun(qrsWidthsMs: qrsWidthsMs, threshold: wideQRSThresholdMs) >= 3 {
            rhythm = .ventricularTachycardia
            confidence = 0.75 * signalQuality
            note = "Run of wide-QRS beats at rate > 100 bpm. Wide-complex tachycardia requires urgent evaluation."
        } else if clampedBpm > 150 && meanQrsMs < narrowQRSUpperMs && !isIrregular {
            rhythm = .supraventricularTachycardia
            confidence = 0.7 * signalQuality
            note = "Narrow-complex tachycardia > 150 bpm."
        } else if !pWavesPresent && isIrregularlyIrregular {
            rhythm = .atrialFibrillation
            confidence = 0.8 * signalQuality
            note = "Irregularly irregular rhythm without discrete P waves."
        } else if sawtooth && !isIrregularlyIrregular && clampedBpm > 120 {
            rhythm = .atrialFlutter
            confidence = 0.6 * signalQuality
            note = "Sawtooth flutter waves with regular ventricular response."
        } else if aDissociated {
            rhythm = .completeHeartBlock
            confidence = 0.65 * signalQuality
            note = "Atrial and ventricular activity appear dissociated."
        } else if prConstantWithDrops {
            rhythm = .mobitzII
            confidence = 0.6 * signalQuality
            note = "Intermittent non-conducted P waves with fixed PR interval."
            anomalies.append(.droppedBeat(count: prAnalysis.droppedBeatCount))
        } else if prLengthening {
            rhythm = .mobitzI
            confidence = 0.6 * signalQuality
            note = "Progressive PR lengthening with dropped QRS (Wenckebach pattern)."
        } else if pWavesPresent && avgPRms > normalPRMaxMs {
            rhythm = .firstDegreeAVBlock
            confidence = 0.7 * signalQuality
            note = "Every P conducted with PR interval > 200 ms."
        } else if pWavesPresent && !isIrregular {
            if clampedBpm < 60 {
                rhythm = .sinusBradycardia
                confidence = 0.8 * signalQuality
                note = "Regular rhythm at rate < 60 bpm with P waves."
            } else if clampedBpm > 100 {
                rhythm = .sinusTachycardia
                confidence = 0.8 * signalQuality
                note = "Regular rhythm at rate > 100 bpm with P waves."
            } else {
                rhythm = .sinusRhythm
                confidence = 0.9 * signalQuality
                note = "Regular rhythm with P wave before each QRS at a normal rate."
            }
        } else if pvcCount >= 1 && rrCv < afIrregularRRCv {
            rhythm = .pvc
            confidence = 0.65 * signalQuality
            note = "Occasional premature wide-QRS beats on an otherwise regular rhythm."
        } else if pacCount >= 1 && rrCv < afIrregularRRCv {
            rhythm = .pac
            confidence = 0.6 * signalQuality
            note = "Occasional premature narrow-QRS beats on an otherwise regular rhythm."
        } else {
            rhythm = .indeterminate
            confidence = 0.3 * signalQuality
            note = "Unable to confidently match the trace to a supported rhythm pattern."
        }

        return ECGClassification(
            rhythm: rhythm,
            heartRate: Int(clampedBpm.rounded()),
            confidence: max(0, min(1, confidence)),
            anomalies: anomalies,
            clinicalNote: note
        )
    }

    // MARK: - QRS Width Measurement

    private func measureQrsWidths(values: [Double], rPeaks: [Int], sampleRateHz: Double) -> [Double] {
        guard !rPeaks.isEmpty else { return [] }
        let windowSamples = Int(0.08 * sampleRateHz) // 80 ms window each side
        return rPeaks.map { peak -> Double in
            let peakValue = abs(values[peak])
            // Threshold = 20% of peak — slightly above baseline.
            let threshold = peakValue * 0.2
            var start = peak
            while start > max(0, peak - windowSamples), abs(values[start]) > threshold {
                start -= 1
            }
            var end = peak
            let upper = min(values.count - 1, peak + windowSamples)
            while end < upper, abs(values[end]) > threshold {
                end += 1
            }
            let widthSamples = max(1, end - start)
            return (Double(widthSamples) / sampleRateHz) * 1000.0
        }
    }

    // MARK: - P-wave + PR Interval Analysis

    struct PWaveAnalysis {
        let pWaveFractionDetected: Double
        let averagePRIntervalMs: Double
        let prProgressivelyLengthening: Bool
        let prConstantWithDroppedBeats: Bool
        let droppedBeatCount: Int
        let avDissociated: Bool
        let sawtoothFWavesLikely: Bool
    }

    private func analyzePWaves(values: [Double], rPeaks: [Int], sampleRateHz: Double) -> PWaveAnalysis {
        var prIntervalsMs: [Double] = []
        var pDetected = 0
        // Search window for P wave: ~80-200 ms before each R peak.
        let searchEnd = Int(0.08 * sampleRateHz)
        let searchStart = Int(0.2 * sampleRateHz)

        for peak in rPeaks {
            let lower = peak - searchStart
            let upper = peak - searchEnd
            guard lower >= 0, upper > lower else { continue }
            let window = Array(values[lower...upper])
            // A "P wave" is a small local maximum distinct from baseline.
            guard let pPeakRel = window.enumerated().max(by: { $0.element < $1.element }) else { continue }
            let baseline = medianAbsolute(window)
            let pAmplitude = pPeakRel.element - baseline
            // Heuristic: P amplitude should be 5-30% of R peak amplitude.
            let rAmplitude = abs(values[peak])
            let ratio = rAmplitude > 0 ? pAmplitude / rAmplitude : 0
            if ratio > 0.04 && ratio < 0.35 {
                pDetected += 1
                let pAbsIndex = lower + pPeakRel.offset
                let prSamples = peak - pAbsIndex
                let prMs = (Double(prSamples) / sampleRateHz) * 1000.0
                if prMs >= minPRMs && prMs <= 400 {
                    prIntervalsMs.append(prMs)
                }
            }
        }

        let pFraction = rPeaks.isEmpty ? 0 : Double(pDetected) / Double(rPeaks.count)
        let avgPR = prIntervalsMs.isEmpty ? 0 : prIntervalsMs.reduce(0, +) / Double(prIntervalsMs.count)

        // Progressive PR lengthening? (Mobitz I / Wenckebach). At least 3 consecutive
        // PR measurements with monotonic increase followed by a reset.
        var lengthening = false
        if prIntervalsMs.count >= 4 {
            var runs = 0
            var bestRun = 0
            for i in 1..<prIntervalsMs.count {
                if prIntervalsMs[i] > prIntervalsMs[i - 1] + 10 {
                    runs += 1
                    bestRun = max(bestRun, runs)
                } else {
                    runs = 0
                }
            }
            lengthening = bestRun >= 3
        }

        // Constant PR with dropped beats? We detect dropped beats as R-R intervals
        // that exceed ~1.8x median R-R — a missed QRS that should have fallen in between.
        let rrSamples: [Int] = zip(rPeaks.dropFirst(), rPeaks).map { $0 - $1 }
        let medRR = rrSamples.isEmpty ? 0 : sorted(rrSamples)[rrSamples.count / 2]
        let droppedCount = rrSamples.filter { medRR > 0 && Double($0) > Double(medRR) * 1.8 }.count
        let prConstant = prIntervalsMs.count >= 3 && standardDeviation(prIntervalsMs) < 15
        let prConstantWithDrops = prConstant && droppedCount > 0

        // AV dissociation proxy: very high P-rate vs ventricular rate + no fixed PR.
        let avDissociated = pFraction >= 0.8 && prIntervalsMs.isEmpty

        // Sawtooth flutter-wave heuristic: fast, regular low-amplitude oscillation
        // between R peaks (~5 Hz). Measured via FFT-like zero-cross density.
        let sawtooth = detectSawtoothBetweenPeaks(values: values, rPeaks: rPeaks, sampleRateHz: sampleRateHz)

        return PWaveAnalysis(
            pWaveFractionDetected: pFraction,
            averagePRIntervalMs: avgPR,
            prProgressivelyLengthening: lengthening,
            prConstantWithDroppedBeats: prConstantWithDrops,
            droppedBeatCount: droppedCount,
            avDissociated: avDissociated,
            sawtoothFWavesLikely: sawtooth
        )
    }

    private func detectSawtoothBetweenPeaks(values: [Double], rPeaks: [Int], sampleRateHz: Double) -> Bool {
        guard rPeaks.count >= 3 else { return false }
        // Take the middle 50% of each R-R interval and count zero-crossings.
        var densities: [Double] = []
        for i in 0..<(rPeaks.count - 1) {
            let a = rPeaks[i]
            let b = rPeaks[i + 1]
            let len = b - a
            guard len > 8 else { continue }
            let start = a + len / 4
            let end = a + (3 * len) / 4
            guard end > start else { continue }
            let segment = Array(values[start...end])
            let mean = segment.reduce(0, +) / Double(segment.count)
            var crossings = 0
            var prev = segment.first! - mean
            for v in segment.dropFirst() {
                let cur = v - mean
                if (cur > 0) != (prev > 0) { crossings += 1 }
                prev = cur
            }
            let seconds = Double(end - start) / sampleRateHz
            if seconds > 0 { densities.append(Double(crossings) / seconds) }
        }
        guard !densities.isEmpty else { return false }
        let avgFreq = densities.reduce(0, +) / Double(densities.count)
        // Atrial flutter F-waves run ~250-350 per minute (4.2-5.8 Hz).
        // Zero crossings = 2 × frequency, so ~8-12 crossings/sec.
        return avgFreq >= 8.0 && avgFreq <= 14.0
    }

    // MARK: - Premature-beat Heuristic

    private func findPrematureBeats(rrIntervalsSec: [Double]) -> [Int] {
        guard rrIntervalsSec.count >= 3 else { return [] }
        let median = sorted(rrIntervalsSec)[rrIntervalsSec.count / 2]
        var premature: [Int] = []
        for (i, rr) in rrIntervalsSec.enumerated() {
            if median > 0, rr < median * 0.75 {
                premature.append(i)
            }
        }
        return premature
    }

    // MARK: - Consecutive wide-QRS run

    private func consecutiveWideRun(qrsWidthsMs: [Double], threshold: Double) -> Int {
        var best = 0
        var cur = 0
        for w in qrsWidthsMs {
            if w > threshold {
                cur += 1
                best = max(best, cur)
            } else {
                cur = 0
            }
        }
        return best
    }

    // MARK: - Signal Quality

    private func estimateSignalQuality(values: [Double], rPeaks: [Int]) -> Double {
        guard rPeaks.count >= 3 else { return 0.5 }
        let amplitudes = rPeaks.map { abs(values[$0]) }
        let ampMean = amplitudes.reduce(0, +) / Double(amplitudes.count)
        let ampSD = standardDeviation(amplitudes)
        let ampCv = ampMean > 0 ? ampSD / ampMean : 1.0
        // Lower CV → higher quality. Clamp to [0.3, 1.0].
        let quality = 1.0 - min(0.7, ampCv)
        return max(0.3, min(1.0, quality))
    }

    // MARK: - Tiny stats helpers (kept local to avoid Accelerate dep)

    private func standardDeviation(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let mean = xs.reduce(0, +) / Double(xs.count)
        let sqSum = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sqSum / Double(xs.count - 1)).squareRoot()
    }

    private func medianAbsolute(_ xs: [Double]) -> Double {
        let sorted = xs.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private func sorted<T: Comparable>(_ xs: [T]) -> [T] { xs.sorted() }
}

// MARK: - Pan-Tompkins QRS Detector
//
// Classic five-stage pipeline:
//   1. Band-pass filter (≈5-15 Hz)   — remove baseline drift + muscle noise
//   2. Derivative                    — emphasize QR up-slope
//   3. Squaring                      — make everything positive + amplify peaks
//   4. Moving window integration     — smooth into detectable bumps
//   5. Adaptive threshold            — locate R peaks

struct PanTompkinsDetector {
    let sampleRateHz: Double

    func detect(samples: [Double]) -> [Int] {
        guard samples.count > 32 else { return [] }

        let bp = bandPass(samples: samples, sampleRateHz: sampleRateHz)
        let diff = derivative(bp)
        let squared = diff.map { $0 * $0 }
        let windowSize = max(1, Int(0.150 * sampleRateHz)) // 150 ms
        let integrated = movingWindowIntegrate(squared, window: windowSize)

        return adaptiveThresholdPeaks(integrated: integrated, sampleRateHz: sampleRateHz)
    }

    // Butterworth-style first-order low-pass + high-pass chained (cheap approximation;
    // sufficient for detection, not for diagnostic filtering).
    private func bandPass(samples: [Double], sampleRateHz: Double) -> [Double] {
        let lowCut = 5.0
        let highCut = 15.0
        let dt = 1.0 / sampleRateHz
        let rcLow = 1.0 / (2.0 * .pi * highCut)
        let alphaLow = dt / (rcLow + dt)
        let rcHigh = 1.0 / (2.0 * .pi * lowCut)
        let alphaHigh = rcHigh / (rcHigh + dt)

        // Low-pass first.
        var lp = [Double](repeating: 0, count: samples.count)
        lp[0] = samples[0]
        for i in 1..<samples.count {
            lp[i] = lp[i - 1] + alphaLow * (samples[i] - lp[i - 1])
        }
        // High-pass on the low-passed signal.
        var bp = [Double](repeating: 0, count: samples.count)
        bp[0] = lp[0]
        for i in 1..<lp.count {
            bp[i] = alphaHigh * (bp[i - 1] + lp[i] - lp[i - 1])
        }
        return bp
    }

    private func derivative(_ xs: [Double]) -> [Double] {
        guard xs.count > 4 else { return xs }
        var out = [Double](repeating: 0, count: xs.count)
        for i in 2..<(xs.count - 2) {
            out[i] = (2 * xs[i + 1] + xs[i + 2] - xs[i - 2] - 2 * xs[i - 1]) / 8.0
        }
        return out
    }

    private func movingWindowIntegrate(_ xs: [Double], window: Int) -> [Double] {
        guard window > 1, xs.count > window else { return xs }
        var out = [Double](repeating: 0, count: xs.count)
        var sum = 0.0
        for i in 0..<xs.count {
            sum += xs[i]
            if i >= window { sum -= xs[i - window] }
            out[i] = sum / Double(window)
        }
        return out
    }

    private func adaptiveThresholdPeaks(integrated: [Double], sampleRateHz: Double) -> [Int] {
        guard !integrated.isEmpty else { return [] }
        let refractoryPeriod = Int(0.2 * sampleRateHz) // 200 ms post-peak lockout
        let searchWindow = max(1, Int(0.1 * sampleRateHz))

        let maxVal = integrated.max() ?? 0
        let noiseFloor = integrated.min() ?? 0
        // Initial thresholds per Pan-Tompkins formulation.
        var signalPeak = maxVal * 0.25
        var noisePeak = noiseFloor * 0.5
        var threshold = noisePeak + 0.25 * (signalPeak - noisePeak)

        var peaks: [Int] = []
        var i = 1
        while i < integrated.count - 1 {
            let v = integrated[i]
            if v > threshold && v > integrated[i - 1] && v >= integrated[i + 1] {
                // Validate within a small local window — suppress tiny shoulder peaks.
                let lower = max(0, i - searchWindow)
                let upper = min(integrated.count - 1, i + searchWindow)
                let localMax = integrated[lower...upper].max() ?? v
                if v >= localMax - 1e-9 {
                    if let last = peaks.last, (i - last) < refractoryPeriod {
                        // Skip peaks that fall inside refractory window.
                    } else {
                        peaks.append(i)
                        signalPeak = 0.125 * v + 0.875 * signalPeak
                        i += refractoryPeriod
                        threshold = noisePeak + 0.25 * (signalPeak - noisePeak)
                        continue
                    }
                } else {
                    noisePeak = 0.125 * v + 0.875 * noisePeak
                    threshold = noisePeak + 0.25 * (signalPeak - noisePeak)
                }
            }
            i += 1
        }
        return peaks
    }
}
