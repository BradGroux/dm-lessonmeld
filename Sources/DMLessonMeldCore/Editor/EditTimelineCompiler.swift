import Foundation

public enum EditTimelineCompiler {
    public static func retainedRanges(sourceRange: EditTimeRange, cuts: [TimelineCut]) -> [EditTimeRange] {
        let enabledCuts = cuts
            .filter(\.isEnabled)
            .map(\.range)
            .filter { $0.overlaps(sourceRange) }
            .sorted { $0.startSeconds < $1.startSeconds }

        guard !enabledCuts.isEmpty else {
            return [sourceRange]
        }

        var retained: [EditTimeRange] = []
        var cursor = sourceRange.startSeconds
        let sourceEnd = sourceRange.endSeconds

        for cut in enabledCuts {
            let cutStart = max(cut.startSeconds, sourceRange.startSeconds)
            let cutEnd = min(cut.endSeconds, sourceEnd)
            if cutStart > cursor {
                retained.append(EditTimeRange(startSeconds: cursor, endSeconds: cutStart))
            }
            cursor = max(cursor, cutEnd)
        }

        if cursor < sourceEnd {
            retained.append(EditTimeRange(startSeconds: cursor, endSeconds: sourceEnd))
        }

        return retained.filter { $0.durationSeconds > 0 }
    }
}
