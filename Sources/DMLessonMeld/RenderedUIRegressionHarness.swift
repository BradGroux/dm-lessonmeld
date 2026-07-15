#if DEBUG
import AppKit
import ApplicationServices
import AVFoundation
import CoreVideo
import DMLessonMeldCore
import Foundation

@MainActor
enum RenderedUIRegressionHarness {
    private static let loadDelayNanoseconds: UInt64 = 1_000_000_000
    private static let settleDelayNanoseconds: UInt64 = 1_000_000_000

    static func run(
        configuration: RenderedUIRegressionLaunchConfiguration,
        model: ProjectEditorModel,
        annotationOverlay: AnnotationOverlayCoordinator,
        preferences: AppPreferencesController,
        selectInspector: @escaping (EditorInspectorTab) -> Void
    ) async {
        do {
            let outputURL = URL(fileURLWithPath: configuration.outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            let projectURL = try await prepareProject(in: outputURL)
            model.loadProject(projectURL)

            switch configuration.fixtureID {
            case "video-editor-overlays":
                selectInspector(.overlays)
            case "video-editor-captions":
                selectInspector(.captions)
            default:
                selectInspector(.edits)
            }

            if configuration.fixtureID == "annotation-toolbar" {
                annotationOverlay.open(
                    preferences: preferences.snapshot,
                    annotationStoreURL: nil,
                    forceToolbarVisible: true
                )
            }

            try await Task.sleep(nanoseconds: loadDelayNanoseconds)
            resizeMainWindow(for: configuration.fixtureID)
            model.seek(to: 0.5)
            NSApplication.shared.activate(ignoringOtherApps: true)
            try await Task.sleep(nanoseconds: settleDelayNanoseconds)
            try writeArtifacts(configuration: configuration, outputURL: outputURL)
            preferences.markCleanTermination()
            NSApplication.shared.terminate(nil)
        } catch {
            writeHarnessFailure(error, configuration: configuration)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func resizeMainWindow(for fixtureID: String) {
        guard let scenario = UIRegressionFixtures.scenarios.first(where: { $0.id == fixtureID }),
              scenario.surface != .annotationToolbar,
              let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.level == .normal }) else {
            return
        }
        window.setContentSize(NSSize(width: scenario.viewport.width, height: scenario.viewport.height))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private static func prepareProject(in outputURL: URL) async throws -> URL {
        try await Task.detached {
            let projectURL = outputURL.appendingPathComponent("Rendered UI Fixture.dmlm", isDirectory: true)
            let mediaURL = projectURL.appendingPathComponent("media", isDirectory: true)
            try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
            let screenURL = mediaURL.appendingPathComponent("screen.mp4")
            try await RenderedUISyntheticVideoWriter.write(outputURL: screenURL)

            let overlays = OverlayStore(overlays: [
                OverlayItem(
                    id: "ui-regression-overlay",
                    kind: .text,
                    timeRange: EditTimeRange(startSeconds: 0.2, durationSeconds: 1.2),
                    frame: NormalizedEditRect(x: 0.12, y: 0.12, width: 0.42, height: 0.18),
                    opacity: 0.94,
                    zIndex: 10,
                    style: OverlayStyle(
                        text: "Rendered UI regression fixture",
                        fontSize: 24,
                        textColor: .white,
                        fillColor: RGBAColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 0.82),
                        strokeColor: .yellow
                    )
                )
            ])
            let overlaysURL = projectURL.appendingPathComponent("overlays.json")
            try DMLessonJSON.encoder().encode(overlays).write(to: overlaysURL, options: [.atomic])

            let transcript = TranscriptDocument(
                language: "en",
                title: "Rendered UI Fixture",
                segments: [
                    TranscriptSegment(
                        id: "ui-regression-caption",
                        startSeconds: 0.1,
                        endSeconds: 1.6,
                        text: "A deterministic public-safe caption"
                    )
                ]
            )
            let transcriptURL = projectURL.appendingPathComponent("transcript.json")
            try DMLessonJSON.encoder().encode(transcript).write(to: transcriptURL, options: [.atomic])

            let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
            let manifest = ProjectManifest(
                createdAt: fixedDate,
                updatedAt: fixedDate,
                metadata: LessonMetadata(
                    courseTitle: "Regression Course",
                    moduleTitle: "Rendered UI",
                    lessonTitle: "Public-safe Fixture",
                    instructor: "Digital Meld"
                ),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "media/screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                    overlays: ProjectFile(relativePath: "overlays.json", role: .overlays, mimeType: "application/json"),
                    transcripts: [
                        ProjectFile(relativePath: "transcript.json", role: .transcript, mimeType: "application/json")
                    ]
                )
            )
            try ProjectBundle.writeManifest(manifest, to: projectURL)
            return projectURL
        }.value
    }

    private static func writeArtifacts(
        configuration: RenderedUIRegressionLaunchConfiguration,
        outputURL: URL
    ) throws {
        guard let scenario = UIRegressionFixtures.scenarios.first(where: { $0.id == configuration.fixtureID }) else {
            throw RenderedUIRegressionError.unknownFixture(configuration.fixtureID)
        }

        let elements = RenderedUIAXCollector.collect()
        let windowFrame = boundingWindowFrame(in: elements)
        let paneLabels: [String]
        if configuration.fixtureID == "video-editor-narrow" {
            paneLabels = ["Video preview", "Timeline pane"]
        } else if scenario.surface == .videoEditor {
            paneLabels = ["Video preview", "Editor inspector", "Timeline pane"]
        } else {
            paneLabels = []
        }
        let findings = RenderedUIAudit.findings(
            elements: elements,
            windowFrame: windowFrame,
            requiredLabels: scenario.requiredPrimaryControls,
            paneLabels: paneLabels,
            ownerLabels: ownerLabels(for: configuration.fixtureID)
        )
        let screenshots = try captureVisibleWindows(to: outputURL)
        let report = RenderedUIRegressionReport(
            fixtureID: configuration.fixtureID,
            appearance: configuration.appearance,
            windowFrame: windowFrame,
            elements: elements,
            findings: findings,
            screenshots: screenshots.map(\.fileName),
            fingerprint: screenshots.first?.fingerprint,
            passed: findings.isEmpty && !screenshots.isEmpty
        )
        let reportURL = outputURL.appendingPathComponent("report.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: [.atomic])

        guard report.passed else {
            throw RenderedUIRegressionError.auditFailed(findings.count)
        }
    }

    private static func ownerLabels(for fixtureID: String) -> [String: String] {
        switch fixtureID {
        case "video-editor-overlays":
            [
                "Cut": "Timeline pane",
                "More timeline actions": "Timeline pane",
                "Video timeline": "Timeline pane",
                "Text": "Editor inspector",
                "Highlight": "Editor inspector",
                "Text overlay": "Video preview",
                "Caption overlay": "Video preview"
            ]
        case "video-editor-captions":
            [
                "Add Caption": "Editor inspector",
                "Burn-in Style": "Editor inspector",
                "Caption overlay": "Video preview",
                "Video timeline": "Timeline pane"
            ]
        case "video-editor-narrow":
            [
                "Cut": "Timeline pane",
                "More timeline actions": "Timeline pane",
                "Timeline scale": "Timeline pane",
                "Video timeline": "Timeline pane"
            ]
        case "annotation-toolbar":
            Dictionary(
                uniqueKeysWithValues: ["Pen", "Highlighter", "Yellow, #FFD733", "Line width", "Clear annotations"]
                    .map { ($0, "LessonMeld annotation toolbar") }
            )
        default:
            [:]
        }
    }

    private static func boundingWindowFrame(in elements: [RenderedUIElement]) -> UILayoutRect {
        let windows = elements.filter { $0.role == "AXWindow" }
        let source = windows.isEmpty ? elements : windows
        guard let first = source.first else { return UILayoutRect(x: 0, y: 0, width: 0, height: 0) }
        let minX = source.map(\.frame.x).min() ?? first.frame.x
        let minY = source.map(\.frame.y).min() ?? first.frame.y
        let maxX = source.map(\.frame.maxX).max() ?? first.frame.maxX
        let maxY = source.map(\.frame.maxY).max() ?? first.frame.maxY
        return UILayoutRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func captureVisibleWindows(to outputURL: URL) throws -> [RenderedUIScreenshotArtifact] {
        var artifacts: [RenderedUIScreenshotArtifact] = []
        let windows = NSApplication.shared.windows
            .filter { $0.isVisible && !$0.frame.isEmpty && $0.contentView != nil }
            .sorted { lhs, rhs in
                if lhs.isKeyWindow != rhs.isKeyWindow { return lhs.isKeyWindow }
                return lhs.level.rawValue > rhs.level.rawValue
            }

        for (index, window) in windows.enumerated() {
            guard let contentView = window.contentView,
                  let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
                continue
            }
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            let fileName = String(format: "%02d-window.png", index)
            try png.write(to: outputURL.appendingPathComponent(fileName), options: [.atomic])
            artifacts.append(RenderedUIScreenshotArtifact(
                fileName: fileName,
                fingerprint: fingerprint(for: bitmap)
            ))
        }
        return artifacts
    }

    private static func fingerprint(for bitmap: NSBitmapImageRep) -> RenderedUIScreenshotFingerprint {
        let columns = 8
        let rows = 6
        var luminance: [Double] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let x = min(bitmap.pixelsWide - 1, max(0, (column * bitmap.pixelsWide + bitmap.pixelsWide / 2) / columns))
                let y = min(bitmap.pixelsHigh - 1, max(0, (row * bitmap.pixelsHigh + bitmap.pixelsHigh / 2) / rows))
                let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                let value = color.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent } ?? 0
                luminance.append((value * 10_000).rounded() / 10_000)
            }
        }
        return RenderedUIScreenshotFingerprint(columns: columns, rows: rows, luminance: luminance)
    }

    private static func writeHarnessFailure(
        _ error: Error,
        configuration: RenderedUIRegressionLaunchConfiguration
    ) {
        let outputURL = URL(fileURLWithPath: configuration.outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let message = "Rendered UI regression harness failed: \(error.localizedDescription)\n"
        try? Data(message.utf8).write(to: outputURL.appendingPathComponent("harness-error.txt"), options: [.atomic])
    }
}

private struct RenderedUIRegressionReport: Codable {
    var fixtureID: String
    var appearance: RenderedUIRegressionAppearance
    var windowFrame: UILayoutRect
    var elements: [RenderedUIElement]
    var findings: [RenderedUIFinding]
    var screenshots: [String]
    var fingerprint: RenderedUIScreenshotFingerprint?
    var passed: Bool
}

private struct RenderedUIScreenshotArtifact {
    var fileName: String
    var fingerprint: RenderedUIScreenshotFingerprint
}

private enum RenderedUIRegressionError: LocalizedError {
    case unknownFixture(String)
    case auditFailed(Int)
    case videoWriterFailed(String)
    case pixelBufferCreationFailed(CVReturn)

    var errorDescription: String? {
        switch self {
        case .unknownFixture(let fixture): "Unknown rendered UI fixture: \(fixture)"
        case .auditFailed(let count): "Rendered UI audit reported \(count) finding(s)."
        case .videoWriterFailed(let message): "Synthetic video writer failed: \(message)"
        case .pixelBufferCreationFailed(let status): "Synthetic video pixel buffer failed with status \(status)."
        }
    }
}

private enum RenderedUIAXCollector {
    static func collect() -> [RenderedUIElement] {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var collected: [RenderedUIElement] = []
        collect(app, depth: 0, into: &collected)
        return collected
    }

    private static func collect(_ element: AXUIElement, depth: Int, into collected: inout [RenderedUIElement]) {
        guard depth < 40, collected.count < 4_000 else { return }
        let role = stringAttribute(element, attribute: kAXRoleAttribute) ?? ""
        let label = [
            stringAttribute(element, attribute: kAXTitleAttribute),
            stringAttribute(element, attribute: kAXDescriptionAttribute),
            stringAttribute(element, attribute: kAXValueAttribute),
            stringAttribute(element, attribute: kAXHelpAttribute)
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        if let frame = frameAttribute(element), !frame.isEmpty {
            collected.append(RenderedUIElement(label: label, role: role, frame: frame))
        }
        guard let children = attribute(element, attribute: kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children {
            collect(child, depth: depth + 1, into: &collected)
        }
    }

    private static func attribute(_ element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func stringAttribute(_ element: AXUIElement, attribute attributeName: String) -> String? {
        attribute(element, attribute: attributeName) as? String
    }

    private static func frameAttribute(_ element: AXUIElement) -> UILayoutRect? {
        guard let positionReference = attribute(element, attribute: kAXPositionAttribute),
              let sizeReference = attribute(element, attribute: kAXSizeAttribute),
              CFGetTypeID(positionReference) == AXValueGetTypeID(),
              CFGetTypeID(sizeReference) == AXValueGetTypeID() else {
            return nil
        }
        let positionValue = positionReference as! AXValue
        let sizeValue = sizeReference as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return UILayoutRect(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }
}

private enum RenderedUISyntheticVideoWriter {
    static func write(outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let size = CGSize(width: 640, height: 360)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        guard writer.canAdd(input) else {
            throw RenderedUIRegressionError.videoWriterFailed("video input could not be added")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw RenderedUIRegressionError.videoWriterFailed(writer.error?.localizedDescription ?? "startWriting returned false")
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let pixelBuffer = try makePixelBuffer(size: size, frame: frame)
            let time = CMTime(value: CMTimeValue(frame), timescale: 12)
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw RenderedUIRegressionError.videoWriterFailed(writer.error?.localizedDescription ?? "frame append returned false")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw RenderedUIRegressionError.videoWriterFailed(writer.error?.localizedDescription ?? "finishWriting did not complete")
        }
    }

    private static func makePixelBuffer(size: CGSize, frame: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw RenderedUIRegressionError.pixelBufferCreationFailed(status)
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw RenderedUIRegressionError.videoWriterFailed("pixel buffer base address is missing")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                pointer[offset] = UInt8(48 + (frame % 3) * 8)
                pointer[offset + 1] = UInt8(38 + (y * 42 / max(height, 1)))
                pointer[offset + 2] = UInt8(24 + (x * 54 / max(width, 1)))
                pointer[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
}
#endif
