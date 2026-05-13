import AppKit
import DMLessonMeldCore
import Foundation

@MainActor
final class InteractionMetadataCaptureSession: @unchecked Sendable {
    private var recorder: InteractionMetadataRecorder
    private var timer: Timer?
    private var monitors: [Any] = []
    private var pausedAt: TimeInterval?

    init(captureRect: CGRect, rendersCursorPointer: Bool) {
        recorder = InteractionMetadataRecorder(
            startTimestamp: ProcessInfo.processInfo.systemUptime,
            captureRect: captureRect,
            rendersCursorPointer: rendersCursorPointer
        )
    }

    func start() {
        guard timer == nil, monitors.isEmpty else { return }

        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.appendCursorSample()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let clickMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp
        ]
        let keyMask: NSEvent.EventTypeMask = [.keyDown, .keyUp]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask.union(keyMask), handler: { [weak self] event in
            Task { @MainActor in
                self?.append(event)
            }
        }) {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clickMask.union(keyMask), handler: { [weak self] event in
            Task { @MainActor in
                self?.append(event)
            }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    func pause() {
        guard pausedAt == nil else { return }
        pausedAt = ProcessInfo.processInfo.systemUptime
    }

    func resume() {
        guard let pausedAt else { return }
        recorder.addPauseOffset(ProcessInfo.processInfo.systemUptime - pausedAt)
        self.pausedAt = nil
    }

    func stop() -> InteractionMetadataDocument {
        if pausedAt != nil {
            resume()
        }
        appendCursorSample()
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        return recorder.document()
    }

    private func appendCursorSample() {
        guard pausedAt == nil else { return }
        recorder.appendCursorSample(
            point: NSEvent.mouseLocation,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    private func append(_ event: NSEvent) {
        guard pausedAt == nil else { return }

        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            appendClick(event)
        case .keyDown, .keyUp:
            appendKeystroke(event)
        default:
            break
        }
    }

    private func appendClick(_ event: NSEvent) {
        recorder.appendClick(
            point: NSEvent.mouseLocation,
            timestamp: event.timestamp,
            button: clickButton(for: event),
            phase: clickPhase(for: event),
            clickCount: event.clickCount
        )
    }

    private func appendKeystroke(_ event: NSEvent) {
        recorder.appendKeystroke(
            timestamp: event.timestamp,
            keyCode: UInt16(event.keyCode),
            characters: shortcutCharacters(for: event),
            modifiers: keyboardModifiers(from: event.modifierFlags),
            phase: event.type == .keyUp ? .up : .down,
            isRepeat: event.isARepeat
        )
    }

    private func clickButton(for event: NSEvent) -> CursorClickButton {
        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            .left
        case .rightMouseDown, .rightMouseUp:
            .right
        case .otherMouseDown, .otherMouseUp:
            event.buttonNumber == 2 ? .middle : .other
        default:
            .other
        }
    }

    private func clickPhase(for event: NSEvent) -> CursorClickPhase {
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            .up
        default:
            .down
        }
    }

    private func shortcutCharacters(for event: NSEvent) -> String? {
        let shortcutFlags: NSEvent.ModifierFlags = [.command, .option, .control, .function]
        guard !event.modifierFlags.intersection(shortcutFlags).isEmpty else {
            return nil
        }

        let text = event.charactersIgnoringModifiers ?? event.characters
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func keyboardModifiers(from flags: NSEvent.ModifierFlags) -> KeyboardMetadataModifiers {
        var modifiers: KeyboardMetadataModifiers = []
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.capsLock) {
            modifiers.insert(.capsLock)
        }
        if flags.contains(.function) {
            modifiers.insert(.function)
        }
        return modifiers
    }
}
