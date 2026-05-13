import Foundation

public struct WaveformPeak: Codable, Equatable, Sendable {
    public var minimum: Float
    public var maximum: Float

    public init(minimum: Float, maximum: Float) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public var absolutePeak: Float {
        max(abs(minimum), abs(maximum))
    }

    public static func downsample(samples: [Float], targetPeakCount: Int) -> [WaveformPeak] {
        guard targetPeakCount > 0, !samples.isEmpty else {
            return []
        }

        let bucketSize = max(1, Int(ceil(Double(samples.count) / Double(targetPeakCount))))
        var peaks: [WaveformPeak] = []
        peaks.reserveCapacity(min(targetPeakCount, samples.count))

        var startIndex = samples.startIndex
        while startIndex < samples.endIndex, peaks.count < targetPeakCount {
            let endIndex = min(startIndex + bucketSize, samples.endIndex)
            let bucket = samples[startIndex..<endIndex]
            guard let minimum = bucket.min(), let maximum = bucket.max() else {
                break
            }
            peaks.append(WaveformPeak(minimum: minimum, maximum: maximum))
            startIndex = endIndex
        }

        return peaks
    }
}
