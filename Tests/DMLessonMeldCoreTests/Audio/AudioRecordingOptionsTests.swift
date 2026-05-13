import DMLessonMeldCore
import Foundation
import Testing

@Suite("Audio recording options")
struct AudioRecordingOptionsTests {
    @Test("Defaults are local capture friendly")
    func defaults() {
        let options = AudioRecordingOptions()

        #expect(options.sampleRate == 48_000)
        #expect(options.channelCount == 1)
        #expect(options.fileFormat == .caf)
        #expect(options.sampleFormat == .pcmFloat32)
        #expect(options.bitRate == 128_000)
        #expect(options.meteringEnabled)
        #expect(options.waveformPeakCount == 1_024)
    }

    @Test("Source live capture classification is explicit")
    func sourceLiveCaptureClassification() {
        #expect(AudioSource.microphone(deviceID: nil).isLiveCapture)
        #expect(AudioSource.system.isLiveCapture)
        #expect(AudioSource.file(URL(fileURLWithPath: "/tmp/audio.caf")).isLiveCapture == false)
        #expect(AudioSource.none.isLiveCapture == false)
    }

    @Test("Microphone permission request does not crash without bundled usage description")
    func microphonePermissionRequestNeedsUsageDescription() async {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") == nil else {
            return
        }
        let granted = await MicrophonePermission.requestAccess()
        #expect(granted == false)
    }
}
