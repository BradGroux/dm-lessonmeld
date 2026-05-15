import CoreGraphics
import Foundation

public struct UILayoutSize: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }
}

public enum AppUILayoutSurface: String, CaseIterable, Sendable {
    case mainEditor
    case videoEditor
    case recorderControlBar
    case onboarding
    case settings
    case commandPalette

    public var minimumSize: UILayoutSize {
        switch self {
        case .mainEditor:
            UILayoutSize(width: 960, height: 680)
        case .videoEditor:
            UILayoutSize(width: 960, height: 640)
        case .recorderControlBar:
            RecorderControlBarLayout.stableWindowMinimumSize
        case .onboarding:
            UILayoutSize(width: 760, height: 640)
        case .settings:
            UILayoutSize(width: 900, height: 620)
        case .commandPalette:
            UILayoutSize(width: 560, height: 360)
        }
    }
}

public enum RecorderControlBarLayout {
    public static let stableContentWidth: CGFloat = 624
    public static let itemWidth: CGFloat = 38
    public static let itemHeight: CGFloat = 38
    public static let itemGap: CGFloat = 2
    public static let outerPadding: CGFloat = 8
    public static let dividerInset: CGFloat = 6
    public static let dividerWidth: CGFloat = 1

    public static var stableWindowMinimumSize: UILayoutSize {
        UILayoutSize(
            width: stableContentWidth + outerPadding * 2,
            height: itemHeight + outerPadding * 2
        )
    }

    public static func requiredContentWidth(items: Int, dividers: Int) -> CGFloat {
        guard items > 0 else { return 0 }
        let itemWidth = CGFloat(items) * self.itemWidth
        let itemGaps = CGFloat(max(items + dividers - 1, 0)) * itemGap
        let dividerWidth = CGFloat(dividers) * (self.dividerWidth + dividerInset * 2)
        return itemWidth + itemGaps + dividerWidth
    }
}

public struct UILayoutRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func intersects(_ other: UILayoutRect) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        return x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }
}

public struct EditorWorkspaceLayoutSnapshot: Equatable, Sendable {
    public var viewport: UILayoutRect
    public var stage: UILayoutRect
    public var inspector: UILayoutRect?
    public var timeline: UILayoutRect?

    public var visibleRects: [UILayoutRect] {
        [stage, inspector, timeline].compactMap(\.self)
    }

    public var hasOverlap: Bool {
        for leftIndex in visibleRects.indices {
            for rightIndex in visibleRects.indices where rightIndex > leftIndex {
                if visibleRects[leftIndex].intersects(visibleRects[rightIndex]) {
                    return true
                }
            }
        }
        return false
    }

    public static func resolve(
        containerWidth: Double,
        containerHeight: Double,
        preferredInspectorWidth: Double = 420,
        inspectorVisible: Bool = true,
        timelineVisible: Bool = true
    ) -> EditorWorkspaceLayoutSnapshot {
        let layout = EditorWorkspaceLayout.resolve(
            containerWidth: containerWidth,
            containerHeight: containerHeight,
            preferredInspectorWidth: preferredInspectorWidth,
            inspectorVisible: inspectorVisible,
            timelineVisible: timelineVisible
        )
        let stage = UILayoutRect(x: 0, y: 0, width: layout.stageWidth, height: layout.stageHeight)
        let inspector = layout.showsInspector
            ? UILayoutRect(
                x: layout.stageWidth + EditorWorkspaceLayout.paneDividerWidth,
                y: 0,
                width: layout.inspectorWidth,
                height: layout.stageHeight
            )
            : nil
        let timeline = layout.showsTimeline
            ? UILayoutRect(
                x: 0,
                y: layout.stageHeight + EditorWorkspaceLayout.paneDividerWidth,
                width: containerWidth,
                height: layout.timelineHeight
            )
            : nil

        return EditorWorkspaceLayoutSnapshot(
            viewport: UILayoutRect(x: 0, y: 0, width: containerWidth, height: containerHeight),
            stage: stage,
            inspector: inspector,
            timeline: timeline
        )
    }
}

public struct UISmokeScenario: Equatable, Sendable {
    public var id: String
    public var surface: AppUILayoutSurface
    public var viewport: UILayoutSize
    public var requiredPrimaryControls: [String]
    public var exercisesOverlayInspector: Bool
    public var exercisesCaptionInspector: Bool

    public init(
        id: String,
        surface: AppUILayoutSurface,
        viewport: UILayoutSize,
        requiredPrimaryControls: [String],
        exercisesOverlayInspector: Bool = false,
        exercisesCaptionInspector: Bool = false
    ) {
        self.id = id
        self.surface = surface
        self.viewport = viewport
        self.requiredPrimaryControls = requiredPrimaryControls
        self.exercisesOverlayInspector = exercisesOverlayInspector
        self.exercisesCaptionInspector = exercisesCaptionInspector
    }
}

public enum UIRegressionFixtures {
    public static let laptop = UILayoutSize(width: 1180, height: 760)
    public static let desktop = UILayoutSize(width: 1680, height: 980)
    public static let narrow = UILayoutSize(width: 960, height: 640)

    public static let scenarios: [UISmokeScenario] = [
        UISmokeScenario(
            id: "editor-empty",
            surface: .mainEditor,
            viewport: laptop,
            requiredPrimaryControls: ["Record Lesson", "Import Video", "New Project", "Open Project"]
        ),
        UISmokeScenario(
            id: "recorder-setup",
            surface: .recorderControlBar,
            viewport: RecorderControlBarLayout.stableWindowMinimumSize,
            requiredPrimaryControls: ["Display", "Window", "Area", "Camera", "Mic", "Options", "Start"]
        ),
        UISmokeScenario(
            id: "recorder-active",
            surface: .recorderControlBar,
            viewport: RecorderControlBarLayout.stableWindowMinimumSize,
            requiredPrimaryControls: ["Hide", "Annotate", "Flag", "Pause", "Restart", "Delete", "Stop"]
        ),
        UISmokeScenario(
            id: "video-editor-overlays",
            surface: .videoEditor,
            viewport: desktop,
            requiredPrimaryControls: ["Play", "Trim In", "Trim Out", "Cut", "Zoom", "Overlay", "Caption", "Timeline"],
            exercisesOverlayInspector: true
        ),
        UISmokeScenario(
            id: "video-editor-captions",
            surface: .videoEditor,
            viewport: laptop,
            requiredPrimaryControls: ["Play", "Captions", "Add Caption", "Burn-in Style", "Timeline"],
            exercisesCaptionInspector: true
        ),
        UISmokeScenario(
            id: "video-editor-narrow",
            surface: .videoEditor,
            viewport: narrow,
            requiredPrimaryControls: ["Play", "Timeline", "Layout"]
        ),
        UISmokeScenario(
            id: "settings-search",
            surface: .settings,
            viewport: AppUILayoutSurface.settings.minimumSize,
            requiredPrimaryControls: ["Search settings", "Revert Section", "Revert All", "Save All"]
        ),
        UISmokeScenario(
            id: "onboarding-permissions",
            surface: .onboarding,
            viewport: AppUILayoutSurface.onboarding.minimumSize,
            requiredPrimaryControls: ["Capture Permissions", "Check Again", "Use Screen Only", "Continue"]
        ),
        UISmokeScenario(
            id: "command-palette",
            surface: .commandPalette,
            viewport: AppUILayoutSurface.commandPalette.minimumSize,
            requiredPrimaryControls: ["Command search", "Show Main Window", "Settings", "Command Palette"]
        )
    ]
}
