import CoreGraphics
import Foundation

public struct UILayoutSize: Codable, Equatable, Sendable {
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
    case annotationToolbar
    case onboarding
    case settings
    case commandPalette

    public var minimumSize: UILayoutSize {
        switch self {
        case .mainEditor:
            UILayoutSize(width: 960, height: 680)
        case .videoEditor:
            UILayoutSize(width: 960, height: 680)
        case .recorderControlBar:
            RecorderControlBarLayout.stableWindowMinimumSize
        case .annotationToolbar:
            UILayoutSize(width: 96, height: 656)
        case .onboarding:
            UILayoutSize(width: 760, height: 640)
        case .settings:
            UILayoutSize(width: 900, height: 620)
        case .commandPalette:
            UILayoutSize(width: 560, height: 360)
        }
    }
}

public enum TimelineToolbarAction: String, CaseIterable, Hashable, Identifiable, Sendable {
    case backOneSecond
    case forwardOneSecond
    case cut
    case zoom
    case volume
    case speed
    case overlay
    case caption
    case hideCursor
    case delete
    case save

    public var id: Self { self }

    public var title: String {
        switch self {
        case .backOneSecond: "Back 1s"
        case .forwardOneSecond: "Forward 1s"
        case .cut: "Cut"
        case .zoom: "Zoom"
        case .volume: "Volume"
        case .speed: "Speed"
        case .overlay: "Overlay"
        case .caption: "Caption"
        case .hideCursor: "Hide Cursor"
        case .delete: "Delete"
        case .save: "Save"
        }
    }

    public var systemImage: String {
        switch self {
        case .backOneSecond: "backward.frame"
        case .forwardOneSecond: "forward.frame"
        case .cut: "scissors"
        case .zoom: "plus.magnifyingglass"
        case .volume: "speaker.wave.2"
        case .speed: "speedometer"
        case .overlay: "textformat"
        case .caption: "captions.bubble"
        case .hideCursor: "cursorarrow.slash"
        case .delete: "trash"
        case .save: "checkmark.circle"
        }
    }
}

public enum TimelineToolbarPresentation: CaseIterable, Sendable {
    case expanded
    case compact

    public var directActions: [TimelineToolbarAction] {
        switch self {
        case .expanded:
            TimelineToolbarAction.allCases
        case .compact:
            [.backOneSecond, .forwardOneSecond, .cut, .zoom, .delete, .save]
        }
    }

    public var overflowActions: [TimelineToolbarAction] {
        switch self {
        case .expanded:
            []
        case .compact:
            [.volume, .speed, .overlay, .caption, .hideCursor]
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

public struct UILayoutRect: Codable, Equatable, Sendable {
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

    public func contains(_ other: UILayoutRect, tolerance: Double = 0.5) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        return other.x >= x - tolerance
            && other.y >= y - tolerance
            && other.maxX <= maxX + tolerance
            && other.maxY <= maxY + tolerance
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
    public static let narrow = AppUILayoutSurface.videoEditor.minimumSize

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
            id: "annotation-toolbar",
            surface: .annotationToolbar,
            viewport: AppUILayoutSurface.annotationToolbar.minimumSize,
            requiredPrimaryControls: ["LessonMeld annotation toolbar", "Pen", "Highlighter", "Yellow, #FFD733", "Line width", "Undo", "Redo"]
        ),
        UISmokeScenario(
            id: "video-editor-overlays",
            surface: .videoEditor,
            viewport: UILayoutSize(width: 1180, height: 680),
            requiredPrimaryControls: ["Play", "Trim In", "Trim Out", "Cut", "Zoom", "More timeline actions", "Text", "Highlight", "Text overlay", "Caption overlay", "Video timeline"],
            exercisesOverlayInspector: true
        ),
        UISmokeScenario(
            id: "video-editor-captions",
            surface: .videoEditor,
            viewport: UILayoutSize(width: 1180, height: 680),
            requiredPrimaryControls: ["Play", "Add Caption", "Burn-in Style", "Caption overlay", "Video timeline"],
            exercisesCaptionInspector: true
        ),
        UISmokeScenario(
            id: "video-editor-narrow",
            surface: .videoEditor,
            viewport: narrow,
            requiredPrimaryControls: ["Play", "Video timeline", "Cut", "More timeline actions", "Timeline scale", "Layout"]
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

public enum RenderedUIRegressionAppearance: String, Codable, CaseIterable, Sendable {
    case light
    case dark
}

public struct RenderedUIRegressionLaunchConfiguration: Equatable, Sendable {
    public var fixtureID: String
    public var outputDirectory: String
    public var appearance: RenderedUIRegressionAppearance

    public init(fixtureID: String, outputDirectory: String, appearance: RenderedUIRegressionAppearance) {
        self.fixtureID = fixtureID
        self.outputDirectory = outputDirectory
        self.appearance = appearance
    }

    public static func parse(arguments: [String]) -> RenderedUIRegressionLaunchConfiguration? {
        guard let fixtureID = value(after: "--ui-regression-fixture", in: arguments),
              let outputDirectory = value(after: "--ui-regression-output", in: arguments),
              UIRegressionFixtures.scenarios.contains(where: { $0.id == fixtureID }) else {
            return nil
        }
        let appearance = value(after: "--ui-regression-appearance", in: arguments)
            .flatMap(RenderedUIRegressionAppearance.init(rawValue:)) ?? .dark
        return RenderedUIRegressionLaunchConfiguration(
            fixtureID: fixtureID,
            outputDirectory: outputDirectory,
            appearance: appearance
        )
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public struct RenderedUIElement: Codable, Equatable, Sendable {
    public var label: String
    public var role: String
    public var frame: UILayoutRect

    public init(label: String, role: String, frame: UILayoutRect) {
        self.label = label
        self.role = role
        self.frame = frame
    }
}

public enum RenderedUIFindingKind: String, Codable, Sendable {
    case missing
    case clipped
    case overlap
}

public struct RenderedUIFinding: Codable, Equatable, Sendable {
    public var kind: RenderedUIFindingKind
    public var label: String
    public var detail: String

    public init(kind: RenderedUIFindingKind, label: String, detail: String) {
        self.kind = kind
        self.label = label
        self.detail = detail
    }
}

public enum RenderedUIAudit {
    public static func findings(
        elements: [RenderedUIElement],
        windowFrame: UILayoutRect,
        requiredLabels: [String],
        paneLabels: [String],
        ownerLabels: [String: String] = [:]
    ) -> [RenderedUIFinding] {
        var findings: [RenderedUIFinding] = []
        let elementsByLabel = Dictionary(grouping: elements, by: \.label)

        for label in requiredLabels {
            guard let matches = elementsByLabel[label], !matches.isEmpty else {
                findings.append(RenderedUIFinding(
                    kind: .missing,
                    label: label,
                    detail: "Required accessibility label was not rendered."
                ))
                continue
            }
            let visibleMatches = matches.filter { windowFrame.contains($0.frame) }
            guard !visibleMatches.isEmpty else {
                findings.append(RenderedUIFinding(
                    kind: .clipped,
                    label: label,
                    detail: "Rendered frame is outside the owning window."
                ))
                continue
            }
            if let ownerLabel = ownerLabels[label],
               let owners = elementsByLabel[ownerLabel],
               !owners.contains(where: { owner in
                   visibleMatches.contains(where: { owner.frame.contains($0.frame) })
               }) {
                findings.append(RenderedUIFinding(
                    kind: .clipped,
                    label: label,
                    detail: "Rendered frame is outside the \(ownerLabel) pane."
                ))
            }
        }

        let panes = paneLabels.flatMap { elementsByLabel[$0] ?? [] }
        for paneLabel in paneLabels where elementsByLabel[paneLabel] == nil {
            findings.append(RenderedUIFinding(
                kind: .missing,
                label: paneLabel,
                detail: "Named pane accessibility boundary was not rendered."
            ))
        }
        for leftIndex in panes.indices {
            for rightIndex in panes.indices where rightIndex > leftIndex {
                let left = panes[leftIndex]
                let right = panes[rightIndex]
                if left.frame.intersects(right.frame) {
                    findings.append(RenderedUIFinding(
                        kind: .overlap,
                        label: "\(left.label) / \(right.label)",
                        detail: "Rendered pane frames overlap."
                    ))
                }
            }
        }
        return findings
    }
}

public struct RenderedUIScreenshotFingerprint: Codable, Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var luminance: [Double]

    public init(columns: Int, rows: Int, luminance: [Double]) {
        self.columns = columns
        self.rows = rows
        self.luminance = luminance
    }

    public func meanAbsoluteDifference(from other: RenderedUIScreenshotFingerprint) -> Double? {
        guard columns == other.columns,
              rows == other.rows,
              luminance.count == columns * rows,
              other.luminance.count == other.columns * other.rows,
              !luminance.isEmpty else {
            return nil
        }
        let total = zip(luminance, other.luminance).reduce(0.0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        }
        return total / Double(luminance.count)
    }
}
