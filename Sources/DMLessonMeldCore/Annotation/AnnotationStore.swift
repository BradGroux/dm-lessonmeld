import CoreGraphics
import Foundation

public struct AnnotationStore: Codable, Equatable, Sendable {
    public private(set) var annotations: [AnnotationItem]
    public private(set) var isVisible: Bool
    public private(set) var isLocked: Bool

    private var undoStack: [HistoryAction]
    private var redoStack: [HistoryAction]

    public init(annotations: [AnnotationItem] = [], isVisible: Bool = true, isLocked: Bool = false) {
        self.annotations = annotations
        self.isVisible = isVisible
        self.isLocked = isLocked
        undoStack = []
        redoStack = []
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public func annotation(id: AnnotationItem.ID) -> AnnotationItem? {
        annotations.first { $0.id == id }
    }

    public mutating func add(_ annotation: AnnotationItem) {
        guard !isLocked else { return }

        annotations.append(annotation)
        record(.add(annotation))
    }

    @discardableResult
    public mutating func update(_ annotation: AnnotationItem) -> Bool {
        guard !isLocked else { return false }
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return false }

        let previous = annotations[index]
        guard previous != annotation, !previous.isLocked else { return false }

        annotations[index] = annotation
        record(.update(previous: previous, next: annotation))
        return true
    }

    @discardableResult
    public mutating func erase(id: AnnotationItem.ID) -> AnnotationItem? {
        guard !isLocked else { return nil }
        guard let index = annotations.firstIndex(where: { $0.id == id }), !annotations[index].isLocked else { return nil }

        let previous = annotations
        let removed = annotations.remove(at: index)
        record(.remove(previous: previous, removed: [removed]))
        return removed
    }

    @discardableResult
    public mutating func erase(at point: CGPoint, radius: CGFloat, displayID: UInt32? = nil) -> [AnnotationItem] {
        guard !isLocked else { return [] }

        let removed = annotations.filter { annotation in
            guard !annotation.isLocked else { return false }
            if let displayID, annotation.displayID != displayID { return false }
            return annotation.touches(point, radius: radius)
        }
        guard !removed.isEmpty else { return [] }

        let previous = annotations
        let removedIDs = Set(removed.map(\.id))
        annotations.removeAll { removedIDs.contains($0.id) }
        record(.remove(previous: previous, removed: removed))
        return removed
    }

    @discardableResult
    public mutating func clear() -> [AnnotationItem] {
        guard !isLocked else { return [] }

        let removed = annotations.filter { !$0.isLocked }
        guard !removed.isEmpty else { return [] }

        let previous = annotations
        let removedIDs = Set(removed.map(\.id))
        annotations.removeAll { removedIDs.contains($0.id) }
        record(.remove(previous: previous, removed: removed))
        return removed
    }

    @discardableResult
    public mutating func clearAll() -> [AnnotationItem] {
        clear()
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let action = undoStack.popLast() else { return false }

        applyUndo(action)
        redoStack.append(action)
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let action = redoStack.popLast() else { return false }

        applyRedo(action)
        undoStack.append(action)
        return true
    }

    public mutating func setVisibility(_ isVisible: Bool) {
        self.isVisible = isVisible
    }

    public mutating func toggleVisibility() {
        isVisible.toggle()
    }

    public mutating func setLocked(_ isLocked: Bool) {
        self.isLocked = isLocked
    }

    public mutating func toggleLock() {
        isLocked.toggle()
    }

    private mutating func record(_ action: HistoryAction) {
        undoStack.append(action)
        redoStack.removeAll()
    }

    private mutating func applyUndo(_ action: HistoryAction) {
        switch action {
        case .add(let annotation):
            annotations.removeAll { $0.id == annotation.id }
        case .remove(let previous, _):
            annotations = previous
        case .update(let previous, let next):
            replace(id: next.id, with: previous)
        }
    }

    private mutating func applyRedo(_ action: HistoryAction) {
        switch action {
        case .add(let annotation):
            annotations.append(annotation)
        case .remove(_, let removed):
            let removedIDs = Set(removed.map(\.id))
            self.annotations.removeAll { removedIDs.contains($0.id) }
        case .update(let previous, let next):
            replace(id: previous.id, with: next)
        }
    }

    private mutating func replace(id: AnnotationItem.ID, with annotation: AnnotationItem) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        annotations[index] = annotation
    }
}

private enum HistoryAction: Codable, Equatable, Sendable {
    case add(AnnotationItem)
    case remove(previous: [AnnotationItem], removed: [AnnotationItem])
    case update(previous: AnnotationItem, next: AnnotationItem)
}
