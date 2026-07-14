import Foundation

public enum ProjectDirtyArea: String, CaseIterable, Hashable, Sendable {
    case metadata = "Metadata"
    case markers = "Markers"
    case editDecisions = "Timeline edits"
    case editorSettings = "Editor settings"
    case overlays = "Overlays"
    case captions = "Captions"

    public var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

public struct ProjectEditorSettingsDirtySnapshot<
    Canvas: Equatable,
    Cursor: Equatable,
    Camera: Equatable,
    Audio: Equatable,
    Export: Equatable
>: Equatable {
    public var canvas: Canvas
    public var automaticZoomEnabled: Bool
    public var cursor: Cursor
    public var camera: Camera
    public var audio: Audio
    public var export: Export

    public init(
        canvas: Canvas,
        automaticZoomEnabled: Bool,
        cursor: Cursor,
        camera: Camera,
        audio: Audio,
        export: Export
    ) {
        self.canvas = canvas
        self.automaticZoomEnabled = automaticZoomEnabled
        self.cursor = cursor
        self.camera = camera
        self.audio = audio
        self.export = export
    }
}

public struct ProjectEditorDirtyState<Snapshot: Equatable> {
    public private(set) var savedSnapshots: [ProjectDirtyArea: Snapshot]
    public private(set) var currentSnapshots: [ProjectDirtyArea: Snapshot]

    public init(
        savedSnapshots: [ProjectDirtyArea: Snapshot] = [:],
        currentSnapshots: [ProjectDirtyArea: Snapshot] = [:]
    ) {
        self.savedSnapshots = savedSnapshots
        self.currentSnapshots = currentSnapshots
    }

    public var dirtyAreas: Set<ProjectDirtyArea> {
        let areas = Set(savedSnapshots.keys).union(currentSnapshots.keys)
        return Set(areas.filter { savedSnapshots[$0] != currentSnapshots[$0] })
    }

    public mutating func replaceCurrent(with snapshots: [ProjectDirtyArea: Snapshot]) {
        currentSnapshots = snapshots
    }

    public mutating func updateCurrent(_ snapshot: Snapshot, for area: ProjectDirtyArea) {
        currentSnapshots[area] = snapshot
    }

    public mutating func markSaved(_ area: ProjectDirtyArea) {
        if let current = currentSnapshots[area] {
            savedSnapshots[area] = current
        } else {
            savedSnapshots.removeValue(forKey: area)
        }
    }

    public mutating func markAllSaved() {
        savedSnapshots = currentSnapshots
    }

    public mutating func reset() {
        savedSnapshots.removeAll()
        currentSnapshots.removeAll()
    }
}
