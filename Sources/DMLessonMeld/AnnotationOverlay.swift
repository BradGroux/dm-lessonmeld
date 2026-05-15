import AppKit
import Combine
import DMLessonMeldCore
@preconcurrency import ScreenCaptureKit
import SwiftUI

@MainActor
final class AnnotationOverlayCoordinator: NSObject, ObservableObject {
    @Published private(set) var isPresented = false
    var openSettingsHandler: ((LessonMeldSettingsSection) -> Void)?

    private var overlayWindow: AnnotationOverlayWindow?
    private var toolbarController: AnnotationOverlayToolbarWindowController?
    private var session: AnnotationOverlaySession?
    private var annotationStoreURL: URL?
    private var cancellables: Set<AnyCancellable> = []
    private var localEscapeMonitor: Any?

    func toggle(
        preferences: LessonMeldPreferences = LessonMeldPreferences(),
        annotationStoreURL: URL? = nil,
        forceToolbarVisible: Bool = false
    ) {
        isPresented ? close() : open(preferences: preferences, annotationStoreURL: annotationStoreURL, forceToolbarVisible: forceToolbarVisible)
    }

    func open(
        preferences: LessonMeldPreferences = LessonMeldPreferences(),
        annotationStoreURL: URL? = nil,
        forceToolbarVisible: Bool = false
    ) {
        guard let screen = NSScreen.screenContainingMouse ?? NSScreen.main else { return }

        if let overlayWindow, let session {
            if let annotationStoreURL, annotationStoreURL != self.annotationStoreURL {
                close()
            } else {
                if forceToolbarVisible {
                    session.isToolbarVisible = true
                    session.isToolbarCollapsed = false
                }
                show(overlayWindow, on: screen)
                toolbarController?.show(on: screen)
                isPresented = true
                return
            }
        }

        let configuration = AnnotationOverlayConfiguration(
            preferences: preferences.annotation.normalized(),
            tooltipsEnabled: preferences.capture.showRecorderControlTooltips,
            forceToolbarVisible: forceToolbarVisible
        )
        let initialStore = annotationStoreURL.flatMap { try? Self.loadAnnotationStore(at: $0) } ?? AnnotationStore()
        let session = AnnotationOverlaySession(
            displayID: screen.displayID,
            configuration: configuration,
            initialStore: initialStore
        )

        let overlayWindow = AnnotationOverlayWindow(screen: screen)
        overlayWindow.delegate = self
        overlayWindow.onEscape = { [weak self] in
            self?.stopAnnotating()
        }
        overlayWindow.contentViewController = NSHostingController(
            rootView: AnnotationOverlayCanvasView(session: session)
        )

        let toolbarController = AnnotationOverlayToolbarWindowController(
            session: session,
            onClose: { [weak self] in
                self?.close()
            },
            onStopAnnotating: { [weak self] in
                self?.stopAnnotating()
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsHandler?(.annotations)
            }
        )

        self.annotationStoreURL = annotationStoreURL
        self.session = session
        self.overlayWindow = overlayWindow
        self.toolbarController = toolbarController
        wireSession(session, toolbarController: toolbarController)
        installEscapeMonitors()

        show(overlayWindow, on: screen)
        if session.isToolbarVisible {
            toolbarController.show(on: screen)
        }
        updateOverlayInteractivity()
        isPresented = true
    }

    func close() {
        NSCursor.arrow.set()
        cancellables.removeAll()
        removeEscapeMonitors()

        let overlayWindow = self.overlayWindow
        let toolbarController = self.toolbarController

        self.overlayWindow = nil
        self.toolbarController = nil
        session = nil
        annotationStoreURL = nil
        isPresented = false

        toolbarController?.close()
        overlayWindow?.delegate = nil
        overlayWindow?.onEscape = nil
        overlayWindow?.contentViewController = nil
        overlayWindow?.orderOut(nil)
        DispatchQueue.main.async {
            overlayWindow?.close()
        }
    }

    private func wireSession(
        _ session: AnnotationOverlaySession,
        toolbarController: AnnotationOverlayToolbarWindowController
    ) {
        session.$selectedTool
            .sink { [weak self, weak toolbarController] _ in
                self?.updateOverlayInteractivity()
                toolbarController?.refreshAfterContentChange()
            }
            .store(in: &cancellables)

        session.$store
            .dropFirst()
            .sink { [weak self] store in
                self?.persist(store)
                self?.updateOverlayInteractivity()
            }
            .store(in: &cancellables)

        session.$toolbarLayout
            .sink { [weak toolbarController] _ in
                toolbarController?.refreshAfterContentChange()
            }
            .store(in: &cancellables)

        session.$isToolbarCollapsed
            .sink { [weak toolbarController] _ in
                toolbarController?.refreshAfterContentChange()
            }
            .store(in: &cancellables)

        session.$isToolbarVisible
            .dropFirst()
            .sink { [weak toolbarController] isVisible in
                if isVisible {
                    toolbarController?.show()
                } else {
                    toolbarController?.hide()
                }
            }
            .store(in: &cancellables)

        session.$isPinnedToFront
            .sink { [weak toolbarController] _ in
                toolbarController?.applyWindowLevel()
            }
            .store(in: &cancellables)
    }

    private func updateOverlayInteractivity() {
        guard let overlayWindow, let session else { return }
        let capturesMouse = session.selectedTool != .cursor && !session.store.isLocked
        overlayWindow.ignoresMouseEvents = !capturesMouse
        overlayWindow.acceptsMouseMovedEvents = capturesMouse
    }

    private func stopAnnotating() {
        guard let session else { return }
        NSCursor.arrow.set()
        session.selectedTool = .cursor
        session.isToolbarVisible = true
        toolbarController?.show()
        updateOverlayInteractivity()
    }

    private func persist(_ store: AnnotationStore) {
        guard let annotationStoreURL else { return }
        do {
            try Self.writeAnnotationStore(store, to: annotationStoreURL)
        } catch {
            NSLog("Digital Meld LessonMeld annotation store write failed: \(error.localizedDescription)")
        }
    }

    private func show(_ window: NSWindow, on screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
        window.level = .lessonMeldAnnotationOverlay
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func installEscapeMonitors() {
        guard localEscapeMonitor == nil else { return }

        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView {
                return event
            }
            Task { @MainActor in
                self?.stopAnnotating()
            }
            return nil
        }
    }

    private func removeEscapeMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
    }

    private static func loadAnnotationStore(at url: URL) throws -> AnnotationStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AnnotationStore()
        }
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
    }

    private static func writeAnnotationStore(_ store: AnnotationStore, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try DMLessonJSON.encoder().encode(store)
        try data.write(to: url, options: [.atomic])
    }
}

extension AnnotationOverlayCoordinator: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            NSCursor.arrow.set()
            cancellables.removeAll()
            removeEscapeMonitors()
            overlayWindow = nil
            toolbarController = nil
            session = nil
            annotationStoreURL = nil
            isPresented = false
        }
    }
}

@MainActor
private final class AnnotationOverlaySession: ObservableObject {
    @Published var store: AnnotationStore
    @Published var selectedTool: OverlayTool
    @Published var selectedColor: RGBAColor
    @Published var lineWidth: CGFloat
    @Published var textSize: CGFloat = 24
    @Published var toolbarLayout: ToolbarLayout = .vertical
    @Published var isToolbarVisible: Bool
    @Published var isToolbarCollapsed = false
    @Published var isPinnedToFront = true
    @Published var boardMode: OverlayBoardMode?

    private var suppressDrawingUntil: Date?

    let displayID: UInt32
    let palette: [RGBAColor]
    let tooltipsEnabled: Bool

    init(
        displayID: UInt32,
        configuration: AnnotationOverlayConfiguration,
        initialStore: AnnotationStore
    ) {
        self.displayID = displayID
        self.palette = configuration.palette
        self.tooltipsEnabled = configuration.tooltipsEnabled
        store = initialStore
        selectedTool = .cursor
        boardMode = nil
        selectedColor = configuration.initialColor
        lineWidth = configuration.lineWidth
        isToolbarVisible = configuration.toolbarVisible
    }

    var canUndo: Bool { store.canUndo }
    var canRedo: Bool { store.canRedo }

    func add(_ annotation: AnnotationItem) {
        mutateStore { $0.add(annotation) }
    }

    @discardableResult
    func erase(at point: CGPoint, radius: CGFloat) -> [AnnotationItem] {
        var removed: [AnnotationItem] = []
        mutateStore {
            removed = $0.erase(at: point, radius: radius, displayID: displayID)
        }
        return removed
    }

    func undo() {
        mutateStore { _ = $0.undo() }
    }

    func redo() {
        mutateStore { _ = $0.redo() }
    }

    func clearAll() {
        mutateStore { _ = $0.clearAll() }
    }

    func toggleLock() {
        mutateStore { $0.toggleLock() }
    }

    func toggleVisibility() {
        mutateStore { $0.toggleVisibility() }
    }

    func selectTool(_ tool: OverlayTool) {
        suppressDrawingFromToolbarAction()
        switch tool {
        case .whiteboard:
            toggleBoard(.white)
        case .blackboard:
            toggleBoard(.black)
        default:
            selectedTool = tool
        }
    }

    func isToolActive(_ tool: OverlayTool) -> Bool {
        switch tool {
        case .whiteboard:
            boardMode == .white
        case .blackboard:
            boardMode == .black
        default:
            selectedTool == tool
        }
    }

    func suppressDrawingFromToolbarAction(for interval: TimeInterval = 0.45) {
        suppressDrawingUntil = Date().addingTimeInterval(interval)
    }

    func exitToolModeForUtilityAction() {
        suppressDrawingFromToolbarAction(for: 1.25)
        selectedTool = .cursor
    }

    func shouldSuppressDrawingFromToolbarAction() -> Bool {
        guard let suppressDrawingUntil else { return false }
        if Date() < suppressDrawingUntil {
            return true
        }
        self.suppressDrawingUntil = nil
        return false
    }

    func copyAnnotatedScreenToPasteboard() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first,
                  let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) ?? NSScreen.main
            else {
                return false
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = true

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let nsImage = NSImage(cgImage: image, size: screen.frame.size)
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([nsImage])
        } catch {
            NSLog("Digital Meld LessonMeld screenshot copy failed: \(error.localizedDescription)")
            return false
        }
    }

    private func toggleBoard(_ mode: OverlayBoardMode) {
        if boardMode == mode {
            boardMode = nil
            return
        }

        boardMode = mode
        if selectedTool == .cursor {
            selectedTool = .pen
        }
    }

    private func mutateStore(_ mutation: (inout AnnotationStore) -> Void) {
        var next = store
        mutation(&next)
        store = next
    }
}

private final class AnnotationOverlayWindow: NSPanel {
    var onEscape: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .lessonMeldAnnotationOverlay
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onEscape?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

@MainActor
private final class AnnotationOverlayToolbarWindowController: NSObject, NSWindowDelegate {
    private let session: AnnotationOverlaySession
    private let onClose: () -> Void
    private let onStopAnnotating: () -> Void
    private let onOpenSettings: () -> Void
    private var panel: NSPanel?
    private var toolbarOriginsByDisplayID: [String: CGPoint] = [:]
    private var suppressMovePersistenceUntil: Date?

    init(
        session: AnnotationOverlaySession,
        onClose: @escaping () -> Void,
        onStopAnnotating: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.session = session
        self.onClose = onClose
        self.onStopAnnotating = onStopAnnotating
        self.onOpenSettings = onOpenSettings
    }

    func show(on screen: NSScreen? = nil) {
        let targetScreen = screen ?? panel?.screen ?? NSScreen.screenContainingMouse ?? NSScreen.main
        if panel == nil {
            makePanel(on: targetScreen)
        }
        resizeToFit(screen: targetScreen)
        applyWindowLevel()
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        panel?.delegate = nil
        (panel as? AnnotationOverlayToolbarPanel)?.onEscape = nil
        panel?.contentView = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    func resizeToFit(screen: NSScreen? = nil) {
        guard let panel else { return }
        let targetScreen = screen ?? panel.screen ?? NSScreen.screenContainingMouse ?? NSScreen.main
        let frame = preferredFrame(on: targetScreen, currentFrame: panel.frame)
        setPanelFrame(clampedFrame(frame, on: targetScreen))
    }

    func refreshAfterContentChange() {
        guard panel != nil else { return }
        resizeToFit()
        panel?.contentView?.needsLayout = true
        panel?.orderFrontRegardless()

        Task { @MainActor [weak self] in
            self?.resizeToFit()
            self?.panel?.contentView?.needsLayout = true
            self?.panel?.orderFrontRegardless()
        }
    }

    func findToolbar() {
        guard let panel else {
            show()
            return
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderFrontRegardless()
            NSSound.beep()
            return
        }

        let originalFrame = panel.frame
        let shifted = originalFrame.offsetBy(dx: 14, dy: 0)
        suppressMovePersistence(for: 0.35)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            panel.animator().setFrame(shifted, display: true)
        } completionHandler: {
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.10
                    panel.animator().setFrame(originalFrame, display: true)
                }
            }
        }
    }

    func applyWindowLevel() {
        panel?.level = session.isPinnedToFront ? .lessonMeldAnnotationPinnedToolbar : .lessonMeldAnnotationToolbar
    }

    func moveToNextDisplay() {
        guard let panel else {
            show()
            return
        }
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            NSSound.beep()
            return
        }

        let currentIndex = panel.screen.flatMap { current in
            screens.firstIndex { $0.displayID == current.displayID }
        } ?? 0
        let nextScreen = screens[(currentIndex + 1) % screens.count]
        let size = preferredSize(in: nextScreen.visibleFrame)
        let frame = CGRect(
            x: nextScreen.visibleFrame.midX - size.width / 2,
            y: nextScreen.visibleFrame.maxY - size.height - 18,
            width: size.width,
            height: size.height
        )
        setPanelFrame(clampedFrame(frame, on: nextScreen))
        toolbarOriginsByDisplayID["\(nextScreen.displayID)"] = panel.frame.origin
        panel.orderFrontRegardless()
    }

    private func makePanel(on screen: NSScreen?) {
        let root = AnnotationOverlayToolbarView(
            session: session,
            onClose: onClose,
            onCopyAnnotatedScreen: { [weak self] in
                self?.copyAnnotatedScreen()
            },
            onMoveToNextDisplay: { [weak self] in
                self?.moveToNextDisplay()
            },
            onOpenSettings: onOpenSettings
        )
        let hostingView = AnnotationToolbarHostingView(rootView: root)
        let frame = preferredFrame(on: screen, currentFrame: nil)
        let panel = AnnotationOverlayToolbarPanel(
            contentRect: clampedFrame(frame, on: screen),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = session.isPinnedToFront ? .lessonMeldAnnotationPinnedToolbar : .lessonMeldAnnotationToolbar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.onEscape = { [weak self] in
            self?.onStopAnnotating()
        }
        panel.delegate = self
        self.panel = panel
    }

    private func copyAnnotatedScreen() {
        guard let panel else {
            NSSound.beep()
            return
        }

        let selectedTool = session.selectedTool
        let boardMode = session.boardMode
        let wasVisible = panel.isVisible
        if wasVisible {
            panel.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !(await self.session.copyAnnotatedScreenToPasteboard()) {
                    NSSound.beep()
                }
                if wasVisible {
                    self.panel?.orderFrontRegardless()
                }
                self.session.selectedTool = selectedTool
                self.session.boardMode = boardMode
            }
        }
    }

    private func preferredFrame(on screen: NSScreen?, currentFrame: CGRect?) -> CGRect {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = preferredSize(in: visibleFrame)
        let origin = currentFrame.map { CGPoint(x: $0.minX, y: $0.minY) }
            ?? toolbarOrigin(on: screen, visibleFrame: visibleFrame, size: size)
        return CGRect(origin: origin, size: size)
    }

    private func preferredSize(in visibleFrame: CGRect) -> CGSize {
        if session.isToolbarCollapsed {
            return CGSize(width: 64, height: 44)
        }

        switch session.toolbarLayout {
        case .vertical:
            return CGSize(
                width: 96,
                height: min(estimatedVerticalHeight(), max(260, visibleFrame.height - 16))
            )
        case .horizontal:
            return CGSize(
                width: min(estimatedHorizontalWidth(), max(420, visibleFrame.width - 48)),
                height: 56
            )
        }
    }

    private func estimatedVerticalHeight() -> CGFloat {
        let outerPadding: CGFloat = 12
        let contentBottomPadding: CGFloat = 6
        let spacing: CGFloat = 6
        let button: CGFloat = AnnotationOverlayToolbarView.buttonSize
        let toolRows = ceil(CGFloat(OverlayTool.primaryTools.count) / 2)
        let colorRows = ceil(CGFloat(min(session.palette.count, 8)) / 2)
        let actionRows = ceil(CGFloat(AnnotationOverlayToolbarView.actionButtonCount) / 2)
        let topControlRows: CGFloat = 1
        let dividers: CGFloat = 3
        let stackChildCount: CGFloat = 10
        return outerPadding +
            button +
            gridHeight(rows: topControlRows) +
            gridHeight(rows: toolRows) +
            gridHeight(rows: colorRows) +
            button * 2 +
            gridHeight(rows: actionRows) +
            dividers * 5 +
            CGFloat(max(stackChildCount - 1, 0)) * spacing +
            contentBottomPadding
    }

    private func gridHeight(rows: CGFloat) -> CGFloat {
        let rowCount = max(rows, 1)
        return rowCount * AnnotationOverlayToolbarView.buttonSize + max(rowCount - 1, 0) * 6
    }

    private func estimatedHorizontalWidth() -> CGFloat {
        let padding: CGFloat = 12
        let spacing: CGFloat = 6
        let button = AnnotationOverlayToolbarView.buttonSize
        let dividerCount: CGFloat = 4
        let menuControls: CGFloat = 2
        let fixedButtons: CGFloat = 3
        let tools = CGFloat(OverlayTool.primaryTools.count)
        let colors = CGFloat(min(session.palette.count, 8))
        let actions = CGFloat(AnnotationOverlayToolbarView.actionButtonCount)
        let standardButtonCount = fixedButtons + tools + colors + actions
        return padding +
            standardButtonCount * button +
            menuControls * 60 +
            dividerCount * 7 +
            (standardButtonCount + menuControls + dividerCount - 1) * spacing
    }

    private func toolbarOrigin(on screen: NSScreen?, visibleFrame: CGRect, size: CGSize) -> CGPoint {
        if let screen {
            let key = "\(screen.displayID)"
            if let origin = toolbarOriginsByDisplayID[key] {
                return origin
            }
        }

        switch session.toolbarLayout {
        case .vertical:
            return CGPoint(
                x: visibleFrame.minX + 28,
                y: visibleFrame.midY - size.height / 2
            )
        case .horizontal:
            return CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height - 18
            )
        }
    }

    private func clampedFrame(_ frame: CGRect, on screen: NSScreen?) -> CGRect {
        let visible = screen?.visibleFrame ?? panel?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let x = min(max(frame.minX, visible.minX + 8), max(visible.minX + 8, visible.maxX - frame.width - 8))
        let y = min(max(frame.minY, visible.minY + 8), max(visible.minY + 8, visible.maxY - frame.height - 8))
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private func setPanelFrame(_ frame: CGRect, display: Bool = true, suppressMoveFor interval: TimeInterval = 0.12) {
        guard let panel else { return }
        suppressMovePersistence(for: interval)
        panel.minSize = CGSize(width: 1, height: 1)
        panel.maxSize = CGSize(width: 10_000, height: 10_000)
        panel.setFrame(frame, display: display)
        panel.minSize = frame.size
        panel.maxSize = frame.size
    }

    private func suppressMovePersistence(for interval: TimeInterval) {
        suppressMovePersistenceUntil = Date().addingTimeInterval(interval)
    }

    private var isMovePersistenceSuppressed: Bool {
        guard let suppressMovePersistenceUntil else { return false }
        if Date() < suppressMovePersistenceUntil {
            return true
        }
        self.suppressMovePersistenceUntil = nil
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, !isMovePersistenceSuppressed else { return }
        let key = panel.screen.map { "\($0.displayID)" }
        if let key {
            toolbarOriginsByDisplayID[key] = panel.frame.origin
        }
    }
}

private final class AnnotationOverlayToolbarPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        onEscape?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private final class AnnotationToolbarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) }
    }

    var displayID: UInt32 {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
}

private extension NSWindow.Level {
    static let lessonMeldAnnotationOverlay = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
    static let lessonMeldAnnotationToolbar = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
    static let lessonMeldAnnotationPinnedToolbar = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
    static let lessonMeldAnnotationTooltip = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 3)
}

private struct AnnotationOverlayConfiguration {
    var initialTool: OverlayTool
    var initialColor: RGBAColor
    var palette: [RGBAColor]
    var lineWidth: CGFloat
    var toolbarVisible: Bool
    var tooltipsEnabled: Bool

    init(
        preferences: AnnotationPreferences,
        tooltipsEnabled: Bool,
        forceToolbarVisible: Bool = false
    ) {
        initialTool = OverlayTool(preferences.defaultTool)
        initialColor = RGBAColor(hex: preferences.defaultColorHex) ?? .yellow
        palette = preferences.paletteHexColors.compactMap(RGBAColor.init(hex:))
        if palette.isEmpty {
            palette = [.red, .yellow, .green, .blue, .purple, .white, .black]
        }
        if palette.count % 2 == 1, palette.count < 8 {
            palette.append(.blue)
        }
        lineWidth = CGFloat(preferences.lineWidth)
        toolbarVisible = forceToolbarVisible || preferences.toolbarVisibleOnOverlayOpen
        self.tooltipsEnabled = tooltipsEnabled
    }
}

private struct ActiveTextEntry: Identifiable {
    let id = UUID()
    var origin: CGPoint
    var text: String
    var size: CGSize
}

private struct AnnotationTextEntryView: NSViewRepresentable {
    @Binding var text: String
    @Binding var size: CGSize
    var fontSize: CGFloat
    var color: RGBAColor
    var canvasSize: CGSize
    var origin: CGPoint
    var minimumSize: CGSize
    var maximumHeight: CGFloat
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            size: $size,
            canvasSize: canvasSize,
            origin: origin,
            minimumSize: minimumSize,
            maximumHeight: maximumHeight,
            onCommit: onCommit,
            onCancel: onCancel
        )
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = AnnotationTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: fontSize, weight: .semibold)
        textView.textColor = NSColor(rgba: color)
        textView.backgroundColor = NSColor.black.withAlphaComponent(0.18)
        textView.drawsBackground = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.minSize = minimumSize
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: maximumHeight)
        textView.textContainerInset = CGSize(width: 8, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(
            width: minimumSize.width - (textView.textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.insertionPointColor = NSColor(rgba: color)
        textView.wantsLayer = true
        textView.layer?.cornerRadius = 6
        textView.layer?.borderWidth = 1
        textView.layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        textView.onCommit = onCommit
        textView.onCancel = onCancel

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.size = $size
        context.coordinator.canvasSize = canvasSize
        context.coordinator.origin = origin
        context.coordinator.minimumSize = minimumSize
        context.coordinator.maximumHeight = maximumHeight
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel

        if textView.string != text {
            textView.string = text
        }
        textView.font = .systemFont(ofSize: fontSize, weight: .semibold)
        textView.textColor = NSColor(rgba: color)
        textView.insertionPointColor = NSColor(rgba: color)
        if let textView = textView as? AnnotationTextView {
            textView.onCommit = onCommit
            textView.onCancel = onCancel
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var size: Binding<CGSize>
        var canvasSize: CGSize
        var origin: CGPoint
        var minimumSize: CGSize
        var maximumHeight: CGFloat
        var onCommit: () -> Void
        var onCancel: () -> Void

        init(
            text: Binding<String>,
            size: Binding<CGSize>,
            canvasSize: CGSize,
            origin: CGPoint,
            minimumSize: CGSize,
            maximumHeight: CGFloat,
            onCommit: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.text = text
            self.size = size
            self.canvasSize = canvasSize
            self.origin = origin
            self.minimumSize = minimumSize
            self.maximumHeight = maximumHeight
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            resizeTextView(textView)
        }

        func resizeTextView(_ textView: NSTextView) {
            guard let font = textView.font else { return }

            let inset = textView.textContainerInset
            let horizontalPadding = inset.width * 2 + 2
            let canvasWidth = canvasSize.width > 0 ? canvasSize.width : NSScreen.main?.frame.width ?? 1440
            let availableWidth = max(120, canvasWidth - origin.x - 16)
            let maxWidth = min(availableWidth, canvasWidth - 16)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let measuredText = textView.string.isEmpty ? "Text" : textView.string
            let longestLineWidth = measuredText
                .components(separatedBy: .newlines)
                .map { line in
                    let value = line.isEmpty ? " " : line
                    return ceil((value as NSString).size(withAttributes: attributes).width)
                }
                .max() ?? 0
            let targetWidth = min(max(longestLineWidth + horizontalPadding + 18, minimumSize.width), maxWidth)

            textView.textContainer?.containerSize = CGSize(
                width: targetWidth - horizontalPadding,
                height: CGFloat.greatestFiniteMagnitude
            )

            var targetHeight = textView.frame.height
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)
                targetHeight = min(
                    max(ceil(usedRect.height + inset.height * 2 + 6), minimumSize.height),
                    maximumHeight
                )
            }

            let nextSize = CGSize(width: targetWidth, height: targetHeight)
            if size.wrappedValue != nextSize {
                size.wrappedValue = nextSize
            }
        }
    }
}

private final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.intersection(.shift) == .shift {
                insertText("\n", replacementRange: selectedRange())
                return
            }
            onCommit?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct AnnotationOverlayCanvasView: View {
    @ObservedObject var session: AnnotationOverlaySession
    @State private var draftPoints: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero
    @State private var eraserLocation: CGPoint?
    @State private var activeTextEntry: ActiveTextEntry?

    private let eraserRadius: CGFloat = 18
    private let minimumTextEditorSize = CGSize(width: 220, height: 38)
    private let maximumTextEditorHeight: CGFloat = 280

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let boardMode = session.boardMode {
                    Rectangle()
                        .fill(boardMode.fillColor)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                AnnotationCanvas(
                    annotations: session.store.isVisible ? session.store.annotations : [],
                    draft: draftAnnotation
                )
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .disabled(session.store.isLocked || session.selectedTool == .cursor)

                if let eraserLocation {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                        .background(Circle().fill(.black.opacity(0.18)))
                        .frame(width: eraserRadius * 2, height: eraserRadius * 2)
                        .position(eraserLocation)
                        .allowsHitTesting(false)
                }

                if let activeTextEntry {
	                    AnnotationTextEntryView(
	                        text: Binding(
	                            get: { self.activeTextEntry?.text ?? "" },
	                            set: { self.activeTextEntry?.text = $0 }
	                        ),
	                        size: Binding(
	                            get: { self.activeTextEntry?.size ?? minimumTextEditorSize },
	                            set: { self.activeTextEntry?.size = $0 }
	                        ),
	                        fontSize: session.textSize,
	                        color: session.selectedColor,
	                        canvasSize: canvasSize,
	                        origin: activeTextEntry.origin,
	                        minimumSize: minimumTextEditorSize,
	                        maximumHeight: maximumTextEditorHeight,
	                        onCommit: commitActiveTextEntry,
	                        onCancel: cancelActiveTextEntry
	                    )
	                    .frame(width: activeTextEntry.size.width, height: activeTextEntry.size.height)
	                    .position(textEntryPosition(for: activeTextEntry.origin, size: activeTextEntry.size))
	                    .zIndex(2)
	                }
            }
            .onAppear {
                canvasSize = proxy.size
            }
            .onChange(of: proxy.size) { _, size in
                canvasSize = size
            }
            .onChange(of: session.selectedTool) { _, tool in
                if tool != .text {
                    commitActiveTextEntry()
                }
                if tool == .cursor {
                    clearDraft()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !session.store.isLocked, !session.shouldSuppressDrawingFromToolbarAction() else {
                    clearDraft()
                    return
                }
                switch session.selectedTool {
                case .cursor:
                    clearDraft()
                case .eraser:
                    draftPoints.removeAll()
                    eraserLocation = value.location
                    _ = session.erase(at: value.location, radius: eraserRadius)
                case .pen, .highlighter, .laser:
                    eraserLocation = nil
                    appendDraftPoint(value.location)
                case .line, .rectangle, .ellipse, .arrow, .whiteboard, .blackboard:
                    eraserLocation = nil
                    draftPoints = [value.startLocation, value.location]
                case .text:
                    clearDraft()
                }
            }
            .onEnded { value in
                guard !session.store.isLocked, !session.shouldSuppressDrawingFromToolbarAction() else {
                    clearDraft()
                    return
                }
                switch session.selectedTool {
                case .cursor:
                    clearDraft()
                case .eraser:
                    eraserLocation = nil
                case .pen, .highlighter, .laser:
                    appendDraftPoint(value.location)
                    commitDraft()
                case .line, .rectangle, .ellipse, .arrow, .whiteboard, .blackboard:
                    draftPoints = [value.startLocation, value.location]
                    commitDraft()
                case .text:
                    if activeTextEntry == nil {
                        beginTextEntry(at: value.location)
                    } else {
                        commitActiveTextEntry()
                    }
                }
            }
    }

    private var draftAnnotation: AnnotationItem? {
        guard !draftPoints.isEmpty, session.selectedTool != .eraser, session.selectedTool != .cursor else {
            return nil
        }
        return makeAnnotation(points: draftPoints)
    }

    private func appendDraftPoint(_ point: CGPoint) {
        if draftPoints.last != point {
            draftPoints.append(point)
        }
    }

    private func clearDraft() {
        draftPoints.removeAll()
        eraserLocation = nil
    }

    private func commitDraft() {
        defer { draftPoints.removeAll() }
        guard let annotation = draftAnnotation else { return }
        session.add(annotation)
    }

    private func beginTextEntry(at point: CGPoint) {
        clearDraft()
        activeTextEntry = ActiveTextEntry(
            origin: textEntryOrigin(for: point, size: minimumTextEditorSize),
            text: "",
            size: minimumTextEditorSize
        )
    }

    private func commitActiveTextEntry() {
        guard let entry = activeTextEntry else { return }
        activeTextEntry = nil
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let origin = textEntryOrigin(for: entry.origin, size: entry.size)

        session.add(AnnotationItem(
            displayID: session.displayID,
            kind: .text,
            points: [origin],
            normalizedPoints: AnnotationItem.normalizedCapturePoints(fromCanvasPoints: [origin], canvasSize: canvasSize),
            coordinateSpace: canvasSize == .zero ? .legacyCanvasPoints : .normalizedCapture,
            color: session.selectedColor,
            lineWidth: session.lineWidth,
            text: text,
            textStyle: AnnotationTextStyle(fontSize: session.textSize)
        ))
    }

    private func cancelActiveTextEntry() {
        activeTextEntry = nil
    }

    private func textEntryOrigin(for origin: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, 8), max(8, canvasSize.width - size.width - 8)),
            y: min(max(origin.y, 8), max(8, canvasSize.height - size.height - 8))
        )
    }

    private func textEntryPosition(for origin: CGPoint, size: CGSize) -> CGPoint {
        let origin = textEntryOrigin(for: origin, size: size)
        return CGPoint(
            x: origin.x + size.width / 2,
            y: origin.y + size.height / 2
        )
    }

    private func makeAnnotation(points: [CGPoint]) -> AnnotationItem {
        var kind = session.selectedTool.annotationKind
        var color = session.selectedTool == .laser ? RGBAColor.red : session.selectedColor
        var fillColor: RGBAColor?
        var opacity = session.selectedTool == .highlighter ? 0.45 : 1
        var width = session.selectedTool == .highlighter ? session.lineWidth * 3 : session.lineWidth
        var annotationPoints = points

        if points.count == 1, session.selectedTool != .text {
            annotationPoints = [points[0], CGPoint(x: points[0].x + 0.1, y: points[0].y + 0.1)]
        }

        if session.selectedTool == .whiteboard {
            kind = .whiteboard
            color = .black
            fillColor = RGBAColor(red: 0.96, green: 0.96, blue: 0.92, alpha: 0.96)
            width = 2
            opacity = 1
        }
        if session.selectedTool == .blackboard {
            kind = .blackboard
            color = .white
            fillColor = RGBAColor(red: 0.02, green: 0.025, blue: 0.02, alpha: 0.96)
            width = 2
            opacity = 1
        }

        return AnnotationItem(
            displayID: session.displayID,
            kind: kind,
            points: annotationPoints,
            normalizedPoints: AnnotationItem.normalizedCapturePoints(fromCanvasPoints: annotationPoints, canvasSize: canvasSize),
            coordinateSpace: canvasSize == .zero ? .legacyCanvasPoints : .normalizedCapture,
            color: color,
            fillColor: fillColor,
            lineWidth: width,
            opacity: opacity,
            text: session.selectedTool == .text ? "Text" : nil,
            textStyle: session.selectedTool == .text ? AnnotationTextStyle(fontSize: session.textSize) : nil
        )
    }
}

private struct AnnotationOverlayToolbarView: View {
    static let buttonSize: CGFloat = 32
    static let actionButtonCount = 10

    @ObservedObject var session: AnnotationOverlaySession
    let onClose: () -> Void
    let onCopyAnnotatedScreen: () -> Void
    let onMoveToNextDisplay: () -> Void
    let onOpenSettings: () -> Void

    private let spacing: CGFloat = 6
    private let columns = [
        GridItem(.fixed(buttonSize), spacing: 6),
        GridItem(.fixed(buttonSize), spacing: 6)
    ]

    var body: some View {
        Group {
            if session.isToolbarCollapsed {
                collapsedBody
            } else if session.toolbarLayout == .vertical {
                verticalBody
            } else {
                horizontalBody
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 7, y: 3)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("LessonMeld annotation toolbar")
    }

    private var collapsedBody: some View {
        HStack(spacing: spacing) {
            collapsedDragBar
            iconButton("chevron.right", active: false, label: "Expand annotation toolbar") {
                session.isToolbarCollapsed = false
            }
        }
        .frame(width: 52, height: Self.buttonSize, alignment: .leading)
    }

    private var verticalBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: spacing) {
                dragBar

                LazyVGrid(columns: columns, spacing: spacing) {
                    orientationToggle
                    collapseToggle
                }

                sectionDivider

                LazyVGrid(columns: columns, spacing: spacing) {
                    toolButtons
                }

                sectionDivider

                LazyVGrid(columns: columns, spacing: spacing) {
                    colorButtons
                }

                widthMenu
                textSizeMenu

                sectionDivider

                LazyVGrid(columns: columns, spacing: spacing) {
                    actionButtons
                }
            }
            .padding(.bottom, spacing)
        }
        .frame(width: 72)
    }

    private var horizontalBody: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                dragBar
                orientationToggle
                collapseToggle
                verticalDivider
                toolButtons
                verticalDivider
                colorButtons
                widthMenu
                textSizeMenu
                verticalDivider
                actionButtons
            }
        }
    }

    private var collapsedDragBar: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.32))
                .frame(width: 7, height: 28)
            WindowDragHandle()
        }
        .frame(width: 14, height: Self.buttonSize)
        .contentShape(Rectangle())
        .overlayHelp("Drag toolbar", enabled: session.tooltipsEnabled)
        .accessibilityLabel("Drag toolbar")
    }

    private var dragBar: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.32))
                .frame(
                    width: session.toolbarLayout == .vertical ? 42 : 7,
                    height: session.toolbarLayout == .vertical ? 5 : 28
                )
            WindowDragHandle()
        }
        .frame(
            width: session.toolbarLayout == .vertical ? 62 : 14,
            height: Self.buttonSize
        )
        .contentShape(Rectangle())
        .overlayHelp("Drag toolbar", enabled: session.tooltipsEnabled)
        .accessibilityLabel("Drag toolbar")
    }

    private var orientationToggle: some View {
        iconButton(
            session.toolbarLayout == .vertical ? "arrow.left.and.right" : "arrow.up.and.down",
            active: false,
            label: session.toolbarLayout == .vertical ? "Switch horizontal" : "Switch vertical"
        ) {
            runToolbarAction {
                session.toolbarLayout = session.toolbarLayout == .vertical ? .horizontal : .vertical
            }
        }
    }

    private var collapseToggle: some View {
        iconButton("line.3.horizontal", active: false, label: "Collapse annotation toolbar") {
            runToolbarAction {
                session.isToolbarCollapsed = true
            }
        }
    }

    private var closeButton: some View {
        iconButton("xmark", active: false, label: "Close annotation tools") {
            runToolbarAction(preserveTool: false, onClose)
        }
    }

    @ViewBuilder private var toolButtons: some View {
        ForEach(OverlayTool.primaryTools) { tool in
            iconButton(tool.systemImage, active: session.isToolActive(tool), label: tool.label) {
                NSCursor.arrow.set()
                session.selectTool(tool)
            }
        }
    }

    @ViewBuilder private var colorButtons: some View {
        ForEach(session.palette.prefix(8), id: \.self) { color in
            Button {
                runToolbarAction {
                    session.selectedColor = color
                }
            } label: {
                Circle()
                    .fill(Color(rgba: color))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(session.selectedColor == color ? .white : .white.opacity(0.35), lineWidth: session.selectedColor == color ? 3 : 1)
                    )
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
            }
            .buttonStyle(.plain)
            .overlayHelp(color.accessibilityName, enabled: session.tooltipsEnabled)
            .accessibilityLabel(color.accessibilityName)
            .accessibilityValue(session.selectedColor == color ? "Selected" : "Not selected")
            .accessibilityHint("Sets the annotation color.")
        }
    }

    private var widthMenu: some View {
        Menu {
            ForEach(Self.lineWidthOptions, id: \.self) { width in
                Button("\(Int(width)) px") {
                    session.lineWidth = width
                }
            }
        } label: {
            menuLabel("line.3.horizontal", value: "\(Int(session.lineWidth))")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 60, height: Self.buttonSize)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlayHelp("Line width", enabled: session.tooltipsEnabled)
        .accessibilityLabel("Line width")
        .accessibilityValue("\(Int(session.lineWidth)) pixels")
    }

    private var textSizeMenu: some View {
        Menu {
            ForEach(Self.textSizeOptions, id: \.self) { size in
                Button("\(Int(size)) px") {
                    session.textSize = size
                }
            }
        } label: {
            menuLabel("textformat.size", value: "\(Int(session.textSize))")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 60, height: Self.buttonSize)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlayHelp("Text size", enabled: session.tooltipsEnabled)
        .accessibilityLabel("Text size")
        .accessibilityValue("\(Int(session.textSize)) pixels")
    }

    @ViewBuilder private var actionButtons: some View {
        iconButton("arrow.uturn.backward", active: false, enabled: session.canUndo, label: "Undo") {
            runToolbarAction {
                session.undo()
            }
        }
        iconButton("arrow.uturn.forward", active: false, enabled: session.canRedo, label: "Redo") {
            runToolbarAction {
                session.redo()
            }
        }
        iconButton(session.store.isLocked ? "lock.fill" : "lock.open", active: session.store.isLocked, label: session.store.isLocked ? "Unlock annotations" : "Lock annotations") {
            runToolbarAction {
                session.toggleLock()
            }
        }
        iconButton(session.store.isVisible ? "eye" : "eye.slash", active: false, label: session.store.isVisible ? "Hide annotations" : "Show annotations") {
            runToolbarAction {
                session.toggleVisibility()
            }
        }
        iconButton(session.isPinnedToFront ? "pin.fill" : "pin", active: session.isPinnedToFront, label: session.isPinnedToFront ? "Unpin toolbar" : "Pin toolbar to front") {
            runToolbarAction {
                session.isPinnedToFront.toggle()
            }
        }
        iconButton("rectangle.on.rectangle", active: false, label: "Move toolbar to next display") {
            runToolbarAction(onMoveToNextDisplay)
        }
        iconButton("doc.on.clipboard", active: false, label: "Copy annotated screen") {
            runToolbarAction(preserveTool: false, onCopyAnnotatedScreen)
        }
        iconButton("trash", active: false, enabled: !session.store.annotations.isEmpty, label: "Clear annotations") {
            runToolbarAction {
                session.clearAll()
            }
        }
        iconButton("gearshape", active: false, label: "Open annotation settings") {
            runToolbarAction(preserveTool: false, onOpenSettings)
        }
        closeButton
    }

    private func runToolbarAction(preserveTool: Bool = true, _ action: () -> Void) {
        if preserveTool {
            session.suppressDrawingFromToolbarAction()
        } else {
            session.exitToolModeForUtilityAction()
        }
        action()
    }

    private func iconButton(
        _ systemImage: String,
        active: Bool,
        enabled: Bool = true,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
        }
        .buttonStyle(AnnotationToolbarButtonStyle(active: active))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .overlayHelp(label, enabled: session.tooltipsEnabled)
        .accessibilityLabel(label)
        .accessibilityValue(active ? "Selected" : (enabled ? "Available" : "Disabled"))
        .accessibilityHint(active ? "Current toolbar selection." : "Activates \(label).")
    }

    private func menuLabel(_ systemImage: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .frame(width: 58, height: Self.buttonSize)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(height: 1)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 1)
            .accessibilityHidden(true)
    }

    private static let lineWidthOptions: [CGFloat] = [1, 3, 4, 6, 8, 12, 18, 24]
    private static let textSizeOptions: [CGFloat] = [18, 24, 32, 48, 64]
}

private struct AnnotationToolbarButtonStyle: ButtonStyle {
    var active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.accentColor : Color.white.opacity(configuration.isPressed ? 0.14 : 0.08))
            )
    }
}

private struct AnnotationCanvas: View {
    let annotations: [AnnotationItem]
    let draft: AnnotationItem?

    var body: some View {
        Canvas { context, size in
            for annotation in annotations where annotation.isVisible {
                draw(annotation, in: &context, size: size)
            }
            if let draft {
                draw(draft, in: &context, size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Annotation drawing surface")
    }

    private func draw(_ annotation: AnnotationItem, in context: inout GraphicsContext, size: CGSize) {
        let points = annotation.canvasPoints(for: size)
        let color = Color(rgba: annotation.color).opacity(annotation.opacity)
        let stroke = StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round)

        switch annotation.kind {
        case .pen, .highlighter, .laser:
            context.stroke(polyline(points), with: .color(color), style: stroke)
        case .line:
            context.stroke(endpointLine(points), with: .color(color), style: stroke)
        case .arrow:
            context.stroke(arrowPath(points), with: .color(color), style: stroke)
        case .rectangle:
            let rect = points.boundingRect
            context.stroke(Path(rect), with: .color(color), style: stroke)
        case .ellipse:
            let rect = points.boundingRect
            context.stroke(Path(ellipseIn: rect), with: .color(color), style: stroke)
        case .whiteboard, .blackboard:
            let rect = points.boundingRect
            if let fillColor = annotation.fillColor {
                context.fill(Path(rect), with: .color(Color(rgba: fillColor).opacity(fillColor.alpha)))
            }
            context.stroke(Path(rect), with: .color(color.opacity(0.65)), style: stroke)
        case .text:
            guard let point = points.first else { return }
            let style = annotation.textStyle ?? AnnotationTextStyle()
            context.draw(
                Text(annotation.text ?? "Text")
                    .font(.system(size: style.fontSize, weight: style.weight.fontWeight))
                    .foregroundStyle(Color(rgba: annotation.color)),
                at: point,
                anchor: .topLeading
            )
        }
    }

    private func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func endpointLine(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        path.addLine(to: last)
        return path
    }

    private func arrowPath(_ points: [CGPoint]) -> Path {
        var path = endpointLine(points)
        guard let start = points.first, let end = points.last, start != end else { return path }

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 18
        let spread: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let right = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )
        path.move(to: left)
        path.addLine(to: end)
        path.addLine(to: right)
        return path
    }
}

private enum OverlayTool: String, CaseIterable, Identifiable {
    case cursor
    case pen
    case highlighter
    case eraser
    case line
    case rectangle
    case ellipse
    case arrow
    case text
    case laser
    case whiteboard
    case blackboard

    var id: String { rawValue }

    static let primaryTools: [OverlayTool] = [
        .cursor, .pen, .highlighter, .eraser,
        .line, .rectangle, .ellipse, .arrow,
        .text, .laser, .whiteboard, .blackboard
    ]

    init(_ tool: AnnotationToolID) {
        switch tool {
        case .pen: self = .pen
        case .highlighter: self = .highlighter
        case .line: self = .line
        case .rectangle: self = .rectangle
        case .ellipse: self = .ellipse
        case .arrow: self = .arrow
        case .text: self = .text
        case .laser: self = .laser
        case .eraser: self = .eraser
        case .whiteboard: self = .whiteboard
        case .blackboard: self = .blackboard
        }
    }

    var annotationKind: AnnotationKind {
        switch self {
        case .cursor, .pen:
            .pen
        case .highlighter:
            .highlighter
        case .eraser:
            .pen
        case .line:
            .line
        case .rectangle:
            .rectangle
        case .ellipse:
            .ellipse
        case .arrow:
            .arrow
        case .text:
            .text
        case .laser:
            .laser
        case .whiteboard:
            .whiteboard
        case .blackboard:
            .blackboard
        }
    }

    var label: String {
        switch self {
        case .cursor: "Cursor"
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .line: "Line"
        case .rectangle: "Box"
        case .ellipse: "Circle or ellipse"
        case .arrow: "Arrow"
        case .text: "Text"
        case .laser: "Laser pointer"
        case .whiteboard: "Whiteboard"
        case .blackboard: "Blackboard"
        }
    }

    var systemImage: String {
        switch self {
        case .cursor: "cursorarrow"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .arrow: "arrow.up.right"
        case .text: "textformat"
        case .laser: "scope"
        case .whiteboard: "rectangle.fill.on.rectangle.fill"
        case .blackboard: "rectangle.fill"
        }
    }
}

private enum ToolbarLayout {
    case vertical
    case horizontal
}

private enum OverlayBoardMode {
    case white
    case black

    var fillColor: Color {
        switch self {
        case .white:
            Color(red: 0.96, green: 0.96, blue: 0.92).opacity(0.96)
        case .black:
            Color(red: 0.02, green: 0.025, blue: 0.02).opacity(0.96)
        }
    }
}

@MainActor
private final class AnnotationTooltipController {
    static let shared = AnnotationTooltipController()

    private var panel: NSPanel?

    func show(_ text: String, near screenPoint: CGPoint) {
        guard !text.isEmpty else { return }

        let contentView = NSHostingView(rootView: AnnotationTooltipBubble(text: text))
        let size = contentView.fittingSize
        let panel = panel ?? makePanel()
        panel.contentView = contentView
        panel.setFrame(positionedFrame(size: size, near: screenPoint), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .lessonMeldAnnotationTooltip
        return panel
    }

    private func positionedFrame(size: CGSize, near point: CGPoint) -> CGRect {
        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let paddedFrame = visibleFrame.insetBy(dx: 8, dy: 8)
        var origin = CGPoint(x: point.x - size.width / 2, y: point.y + 18)

        if origin.y + size.height > paddedFrame.maxY {
            origin.y = point.y - size.height - 18
        }

        let maxX = max(paddedFrame.minX, paddedFrame.maxX - size.width)
        let maxY = max(paddedFrame.minY, paddedFrame.maxY - size.height)
        origin.x = min(max(origin.x, paddedFrame.minX), maxX)
        origin.y = min(max(origin.y, paddedFrame.minY), maxY)

        return CGRect(origin: origin, size: size)
    }
}

private struct AnnotationTooltipBubble: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 320, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 6, y: 2)
    }
}

private extension View {
    @ViewBuilder
    func overlayHelp(_ text: String, enabled: Bool) -> some View {
        if enabled {
            help(text)
                .accessibilityHint(text)
                .onHover { isHovering in
                    if isHovering {
                        AnnotationTooltipController.shared.show(text, near: NSEvent.mouseLocation)
                    } else {
                        AnnotationTooltipController.shared.hide()
                    }
                }
        } else {
            self
                .accessibilityHint(text)
                .onHover { isHovering in
                    if !isHovering {
                        AnnotationTooltipController.shared.hide()
                    }
                }
        }
    }
}

private extension NSColor {
    convenience init(rgba color: RGBAColor) {
        self.init(
            calibratedRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }
}

private extension RGBAColor {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }), let value = UInt32(raw, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var accessibilityName: String {
        switch self {
        case .yellow: "Yellow"
        case .cyan: "Cyan"
        case .green: "Green"
        case .red: "Red"
        case .purple: "Purple"
        case .white: "White"
        case .black: "Black"
        default: "Color"
        }
    }
}

private extension AnnotationTextWeight {
    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}
