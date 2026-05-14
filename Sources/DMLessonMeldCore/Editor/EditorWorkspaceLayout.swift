import Foundation

public struct EditorWorkspaceLayout: Equatable, Sendable {
    public static let minimumStageWidth = 560.0
    public static let minimumStageHeight = 300.0
    public static let minimumInspectorWidth = 320.0
    public static let maximumInspectorWidth = 560.0
    public static let minimumTimelineHeight = 168.0
    public static let defaultTimelineHeight = 236.0
    public static let paneDividerWidth = 1.0

    public var showsInspector: Bool
    public var showsTimeline: Bool
    public var inspectorWidth: Double
    public var timelineHeight: Double
    public var stageWidth: Double
    public var stageHeight: Double

    public static func resolve(
        containerWidth: Double,
        containerHeight: Double,
        preferredInspectorWidth: Double = 420,
        inspectorVisible: Bool,
        timelineVisible: Bool
    ) -> EditorWorkspaceLayout {
        let safeWidth = max(0, containerWidth)
        let safeHeight = max(0, containerHeight)
        let inspectorWidth = min(max(preferredInspectorWidth, minimumInspectorWidth), maximumInspectorWidth)
        let canShowInspector = inspectorVisible && safeWidth >= minimumStageWidth + inspectorWidth
        let resolvedInspectorWidth = canShowInspector ? inspectorWidth : 0
        let inspectorDividerWidth = canShowInspector ? paneDividerWidth : 0
        let stageWidth = max(0, safeWidth - resolvedInspectorWidth - inspectorDividerWidth)

        let canShowTimeline = timelineVisible && safeHeight >= minimumStageHeight + minimumTimelineHeight
        let timelineHeight = canShowTimeline ? min(defaultTimelineHeight, max(minimumTimelineHeight, safeHeight - minimumStageHeight)) : 0
        let stageHeight = max(minimumStageHeight, safeHeight - timelineHeight)

        return EditorWorkspaceLayout(
            showsInspector: canShowInspector,
            showsTimeline: canShowTimeline,
            inspectorWidth: resolvedInspectorWidth,
            timelineHeight: timelineHeight,
            stageWidth: stageWidth,
            stageHeight: stageHeight
        )
    }
}
