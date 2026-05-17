import AVFoundation
import Foundation

struct RenderAudioMixBuilder {
    static func mix(
        for audioTracks: [InsertedAudioTrack],
        settings: EditorAudioSettings,
        duration: CMTime,
        timelineMapper: TimelineRetimingMapper,
        hasVoiceAudio: Bool
    ) -> AVAudioMix? {
        guard !audioTracks.isEmpty else { return nil }

        let parameters = audioTracks.map { insertedTrack in
            let params = AVMutableAudioMixInputParameters(track: insertedTrack.track)
            let baseGain = baseGain(for: insertedTrack.role, settings: settings)
            params.setVolume(Float(baseGain), at: .zero)

            if insertedTrack.role == .backgroundMusic,
               let backgroundMusic = settings.backgroundMusic,
               backgroundMusic.duckUnderVoice,
               hasVoiceAudio {
                applyVolumeRamp(
                    to: params,
                    range: EditTimeRange(startSeconds: 0, durationSeconds: max(0, duration.seconds)),
                    baseGain: backgroundMusic.gain,
                    targetGain: backgroundMusic.duckedGain,
                    fadeInSeconds: min(backgroundMusic.fadeInSeconds, 1),
                    fadeOutSeconds: min(backgroundMusic.fadeOutSeconds, 1)
                )
            }

            for region in settings.enabledVolumeRegions where regionMatches(region.track, insertedTrack.role) {
                applyVolumeRamp(
                    to: params,
                    range: region.range,
                    timelineMapper: timelineMapper,
                    baseGain: baseGain,
                    targetGain: region.gain,
                    fadeInSeconds: region.fadeInSeconds,
                    fadeOutSeconds: region.fadeOutSeconds
                )
            }
            return params
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }

    private static func baseGain(for role: EditorAudioTrackRole, settings: EditorAudioSettings) -> Double {
        if role == .backgroundMusic {
            return settings.backgroundMusic?.gain ?? 1
        }
        let trackSettings = settings.trackSettings(for: role)
        if trackSettings.isMuted || settings.isSoloMuted(role: role) {
            return 0
        }
        return trackSettings.gain
    }

    private static func regionMatches(_ regionRole: EditorAudioTrackRole, _ trackRole: EditorAudioTrackRole) -> Bool {
        regionRole == .all || regionRole == trackRole
    }

    private static func applyVolumeRamp(
        to params: AVMutableAudioMixInputParameters,
        range: EditTimeRange,
        timelineMapper: TimelineRetimingMapper = TimelineRetimingMapper(),
        baseGain: Double,
        targetGain: Double,
        fadeInSeconds: Double,
        fadeOutSeconds: Double
    ) {
        let mappedRange = timelineMapper.outputRange(forSourceRange: range)
        let startSeconds = max(0, mappedRange.startSeconds)
        let endSeconds = max(startSeconds, mappedRange.endSeconds)
        let durationSeconds = max(0, endSeconds - startSeconds)
        guard durationSeconds > 0 else { return }

        let clampedFadeIn = min(max(0, fadeInSeconds), durationSeconds)
        let clampedFadeOut = min(max(0, fadeOutSeconds), max(0, durationSeconds - clampedFadeIn))
        let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let fadeInEnd = CMTime(seconds: startSeconds + clampedFadeIn, preferredTimescale: 600)
        let fadeOutStart = CMTime(seconds: endSeconds - clampedFadeOut, preferredTimescale: 600)
        let end = CMTime(seconds: endSeconds, preferredTimescale: 600)
        let base = Float(baseGain)
        let target = Float(targetGain)

        if clampedFadeIn > 0 {
            params.setVolumeRamp(
                fromStartVolume: base,
                toEndVolume: target,
                timeRange: CMTimeRange(start: start, end: fadeInEnd)
            )
        } else {
            params.setVolume(target, at: start)
        }

        if fadeOutStart > fadeInEnd {
            params.setVolume(target, at: fadeInEnd)
        }

        if clampedFadeOut > 0 {
            params.setVolumeRamp(
                fromStartVolume: target,
                toEndVolume: base,
                timeRange: CMTimeRange(start: fadeOutStart, end: end)
            )
        }
        params.setVolume(base, at: end)
    }

}

struct InsertedAudioTrack {
    var track: AVMutableCompositionTrack
    var role: EditorAudioTrackRole
}
