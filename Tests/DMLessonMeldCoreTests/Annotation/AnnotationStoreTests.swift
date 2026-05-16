import CoreGraphics
import DMLessonMeldCore
import Foundation
import Testing

@Suite("Annotation store")
struct AnnotationStoreTests {
    @Test("Adds, undoes, and redoes annotations")
    func addUndoRedo() {
        var store = AnnotationStore()
        let item = annotation(kind: .pen, points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)])

        store.add(item)

        #expect(store.annotations == [item])
        #expect(store.canUndo)
        #expect(!store.canRedo)

        let didUndo = store.undo()
        #expect(didUndo)
        #expect(store.annotations.isEmpty)
        #expect(!store.canUndo)
        #expect(store.canRedo)

        let didRedo = store.redo()
        #expect(didRedo)
        #expect(store.annotations == [item])
    }

    @Test("Clear removes unlocked annotations and can be undone")
    func clearUndo() {
        var store = AnnotationStore()
        let first = annotation(kind: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
        let locked = annotation(
            kind: .ellipse,
            points: [CGPoint(x: 200, y: 200), CGPoint(x: 260, y: 260)],
            isLocked: true
        )

        store.add(first)
        store.add(locked)

        let removed = store.clear()

        #expect(removed == [first])
        #expect(store.annotations == [locked])

        let didUndo = store.undo()
        #expect(didUndo)
        #expect(store.annotations == [first, locked])
    }

    @Test("Erase removes touched annotations on the selected display")
    func eraseTouchedAnnotations() {
        var store = AnnotationStore()
        let touched = annotation(
            displayID: 1,
            kind: .line,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        )
        let otherDisplay = annotation(
            displayID: 2,
            kind: .line,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            color: .blue
        )
        let untouched = annotation(
            displayID: 1,
            kind: .rectangle,
            points: [CGPoint(x: 200, y: 200), CGPoint(x: 260, y: 260)],
            color: .green
        )

        store.add(touched)
        store.add(otherDisplay)
        store.add(untouched)

        let removed = store.erase(at: CGPoint(x: 50, y: 2), radius: 8, displayID: 1)

        #expect(removed == [touched])
        #expect(store.annotations == [otherDisplay, untouched])

        let didUndo = store.undo()
        #expect(didUndo)
        #expect(store.annotations.contains(touched))
    }

    @Test("Touch checks cover paths, shapes, text, and invisible items")
    func touches() {
        let path = annotation(kind: .pen, points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], lineWidth: 3)
        let rectangle = annotation(kind: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)])
        let text = annotation(
            kind: .text,
            points: [CGPoint(x: 200, y: 200)],
            text: "Callout",
            textStyle: AnnotationTextStyle(fontSize: 20)
        )
        let hidden = annotation(
            kind: .laser,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            isVisible: false
        )

        #expect(path.touches(CGPoint(x: 50, y: 2), radius: 4))
        #expect(!path.touches(CGPoint(x: 50, y: 20), radius: 4))
        #expect(rectangle.touches(CGPoint(x: 50, y: 50), radius: 0))
        #expect(text.touches(CGPoint(x: 230, y: 210), radius: 0))
        #expect(!hidden.touches(CGPoint(x: 50, y: 0), radius: 10))
    }

    @Test("Update, visibility, lock, and Codable round trip")
    func updateVisibilityLockAndCodable() throws {
        var store = AnnotationStore()
        let original = annotation(kind: .arrow, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        var updated = original
        updated.points = [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)]

        store.add(original)
        let didUpdate = store.update(updated)
        #expect(didUpdate)
        #expect(store.annotation(id: original.id)?.points == updated.points)

        store.toggleVisibility()
        store.setLocked(true)
        #expect(!store.isVisible)
        #expect(store.isLocked)

        store.add(annotation(kind: .pen, points: [CGPoint(x: 1, y: 1)]))
        #expect(store.annotations.count == 1)

        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(AnnotationStore.self, from: data)

        #expect(decoded == store)
    }

    @Test("Timed normalized annotations round trip and convert to canvas points")
    func timedNormalizedAnnotations() throws {
        let item = AnnotationItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            displayID: 1,
            kind: .arrow,
            points: [CGPoint(x: 50, y: 25), CGPoint(x: 150, y: 75)],
            normalizedPoints: [
                NormalizedAnnotationPoint(x: 0.25, y: 0.75),
                NormalizedAnnotationPoint(x: 0.75, y: 0.25)
            ],
            coordinateSpace: .normalizedCapture,
            timeRange: AnnotationTimeRange(startSeconds: 1.5, endSeconds: 4),
            color: .yellow,
            lineWidth: 5,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(item.canvasPoints(for: CGSize(width: 200, height: 100)) == [
            CGPoint(x: 50, y: 25),
            CGPoint(x: 150, y: 75)
        ])
        #expect(!item.isVisible(at: 1.49))
        #expect(item.isVisible(at: 1.5))
        #expect(item.isVisible(at: 3.99))
        #expect(!item.isVisible(at: 4))

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(AnnotationItem.self, from: data)

        #expect(decoded == item)
    }

    @Test("Legacy point annotations decode as canvas coordinates")
    func legacyPointAnnotationsDecode() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000321",
          "displayID": 1,
          "kind": "text",
          "points": [[12, 34]],
          "color": {"red": 1, "green": 0.86, "blue": 0.2, "alpha": 1},
          "lineWidth": 3,
          "opacity": 1,
          "text": "Legacy"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AnnotationItem.self, from: json)

        #expect(decoded.coordinateSpace == .legacyCanvasPoints)
        #expect(decoded.normalizedPoints == nil)
        #expect(decoded.timeRange == nil)
        #expect(decoded.canvasPoints(for: CGSize(width: 200, height: 100)) == [CGPoint(x: 12, y: 34)])
        #expect(decoded.isVisible(at: 10))
    }

    @Test("Tool and kind models include v1 annotation surface")
    func annotationSurfaceCases() {
        let expected: Set<String> = [
            "pen", "highlighter", "line", "rectangle", "ellipse",
            "arrow", "text", "laser", "whiteboard", "blackboard"
        ]

        #expect(Set(AnnotationTool.allCases.map(\.rawValue)) == expected)
        #expect(Set(AnnotationKind.allCases.map(\.rawValue)) == expected)
    }

    @Test("Sidecar writer coalesces debounced writes")
    func sidecarWriterCoalescesDebouncedWrites() async throws {
        let temp = try TemporaryDirectory()
        let url = temp.url.appendingPathComponent("annotations.json")
        let writer = AnnotationSidecarWriter(
            configuration: AnnotationSidecarWriter.Configuration(debounceNanoseconds: 10_000_000)
        )
        var first = AnnotationStore()
        first.add(annotation(kind: .pen, points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]))
        var second = first
        second.add(annotation(kind: .text, points: [CGPoint(x: 20, y: 20)], text: "Final"))

        await writer.schedule(first, to: url)
        await writer.schedule(second, to: url)

        let decoded = try await waitForAnnotationStore(at: url)
        #expect(decoded == second)
    }

    @Test("Sidecar writer flushes pending writes immediately")
    func sidecarWriterFlushesPendingWrites() async throws {
        let temp = try TemporaryDirectory()
        let url = temp.url.appendingPathComponent("annotations.json")
        let writer = AnnotationSidecarWriter(
            configuration: AnnotationSidecarWriter.Configuration(debounceNanoseconds: 60_000_000_000)
        )
        var store = AnnotationStore()
        store.add(annotation(kind: .rectangle, points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)]))

        await writer.schedule(store, to: url)
        try await writer.flush()

        let data = try Data(contentsOf: url)
        let decoded = try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
        #expect(decoded == store)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dm-lessonmeld-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private func waitForAnnotationStore(at url: URL) async throws -> AnnotationStore {
    for _ in 0..<50 {
        if let data = try? Data(contentsOf: url),
           let store = try? DMLessonJSON.decoder().decode(AnnotationStore.self, from: data) {
            return store
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    let data = try Data(contentsOf: url)
    return try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
}

private func annotation(
    displayID: UInt32 = 1,
    kind: AnnotationKind,
    points: [CGPoint],
    color: RGBAColor = .red,
    lineWidth: CGFloat = 3,
    text: String? = nil,
    textStyle: AnnotationTextStyle? = nil,
    isVisible: Bool = true,
    isLocked: Bool = false
) -> AnnotationItem {
    AnnotationItem(
        displayID: displayID,
        kind: kind,
        points: points,
        color: color,
        lineWidth: lineWidth,
        text: text,
        textStyle: textStyle,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        isVisible: isVisible,
        isLocked: isLocked
    )
}
