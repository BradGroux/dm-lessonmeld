import CoreMedia
import Foundation

enum SampleBufferTiming {
    static func adjusted(_ sampleBuffer: CMSampleBuffer, offsetSeconds: TimeInterval) -> CMSampleBuffer {
        guard offsetSeconds > 0 else {
            return sampleBuffer
        }

        var timingCount = 0
        var status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &timingCount
        )
        guard status == noErr, timingCount > 0 else {
            return sampleBuffer
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: timingCount
        )
        status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: timingCount,
            arrayToFill: &timing,
            entriesNeededOut: &timingCount
        )
        guard status == noErr else {
            return sampleBuffer
        }

        let offset = CMTime(seconds: offsetSeconds, preferredTimescale: 600)
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, offset)
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, offset)
            }
        }

        var adjustedBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingCount,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjustedBuffer
        )
        return status == noErr ? adjustedBuffer ?? sampleBuffer : sampleBuffer
    }
}
