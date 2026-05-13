import DMLessonMeldCore
import Testing

@Suite("Waveform peaks")
struct WaveformPeakTests {
    @Test("Downsamples samples into min max buckets")
    func downsamplesSamplesIntoBuckets() {
        let samples: [Float] = [-0.1, 0.3, -0.8, 0.2, 0.1, 0.9, -0.4, 0.5]

        let peaks = WaveformPeak.downsample(samples: samples, targetPeakCount: 3)

        #expect(peaks == [
            WaveformPeak(minimum: -0.8, maximum: 0.3),
            WaveformPeak(minimum: 0.1, maximum: 0.9),
            WaveformPeak(minimum: -0.4, maximum: 0.5)
        ])
        #expect(peaks[0].absolutePeak == 0.8)
    }

    @Test("Handles empty samples and invalid target counts")
    func handlesEmptyInput() {
        #expect(WaveformPeak.downsample(samples: [], targetPeakCount: 8).isEmpty)
        #expect(WaveformPeak.downsample(samples: [0.1, -0.1], targetPeakCount: 0).isEmpty)
    }
}
