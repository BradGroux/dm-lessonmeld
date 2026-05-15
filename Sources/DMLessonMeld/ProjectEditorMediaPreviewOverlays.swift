import AppKit
import AVFoundation
import AVKit
import DMLessonMeldCore
import SwiftUI
import UniformTypeIdentifiers

extension ProjectEditorView {
    @ViewBuilder var canvasPreviewBackground: some View {
        switch model.canvasBackgroundStyle {
        case .none:
            Color.black
        case .solid:
            Color(rgba: model.canvasPrimaryColor)
        case .gradient:
            LinearGradient(
                colors: [Color(rgba: model.canvasPrimaryColor), Color(rgba: model.canvasSecondaryColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .image:
            if let image = model.canvasBackgroundImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
    }

    @ViewBuilder var zoomFocusOverlay: some View {
        if let zoomID = selectedZoomID,
           let zoom = model.zoomRow(id: zoomID),
           let centerX = secondsValue(zoom.centerX),
           let centerY = secondsValue(zoom.centerY),
           let size = secondsValue(zoom.size) {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
                let boxWidth = max(40, contentFrame.width * CGFloat(size))
                let boxHeight = max(40, contentFrame.height * CGFloat(size))
                let focusPoint = EditorNormalizedGeometry.topDownPoint(x: centerX, y: centerY, in: contentFrame)
                let positionX = min(max(focusPoint.x, contentFrame.minX + boxWidth / 2), contentFrame.maxX - boxWidth / 2)
                let positionY = min(max(focusPoint.y, contentFrame.minY + boxHeight / 2), contentFrame.maxY - boxHeight / 2)
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: boxWidth, height: boxHeight)
                    .position(x: positionX, y: positionY)
                    .overlay(alignment: .topLeading) {
                        Text("\(zoom.scale)x")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 10, y: 10)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = Double((value.location.x - contentFrame.minX) / max(contentFrame.width, 1))
                                let y = Double((value.location.y - contentFrame.minY) / max(contentFrame.height, 1))
                                model.updateZoomFocus(
                                    id: zoomID,
                                    centerX: x,
                                    centerY: y
                                )
                            }
                            .onEnded { _ in
                                model.saveEditDecisions()
                            }
                    )
                    .help("Drag to move the selected zoom focus")
            }
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder var overlayPreviewOverlay: some View {
        if !model.overlayRows.isEmpty {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    ForEach(model.overlayRows(at: model.currentTimeSeconds)) { overlay in
                        let frame = overlayPreviewFrame(overlay, in: contentFrame)
                        overlayPreview(overlay)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(selectedTimelineItem == .overlay(overlay.id) ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                if selectedTimelineItem == .overlay(overlay.id) {
                                    overlayResizeHandle()
                                        .offset(x: 5, y: 5)
                                        .gesture(
                                            DragGesture(minimumDistance: 1)
                                                .onChanged { value in
                                                    if activeOverlayResizeDrag?.id != overlay.id {
                                                        activeOverlayResizeDrag = OverlayPreviewResizeDragState(
                                                            id: overlay.id,
                                                            startWidth: secondsValue(overlay.width) ?? 0.2,
                                                            startHeight: secondsValue(overlay.height) ?? 0.15
                                                        )
                                                    }
                                                    guard let drag = activeOverlayResizeDrag, drag.id == overlay.id else { return }
                                                    model.updateOverlayFrame(
                                                        id: overlay.id,
                                                        width: drag.startWidth + Double(value.translation.width / max(contentFrame.width, 1)),
                                                        height: drag.startHeight + Double(value.translation.height / max(contentFrame.height, 1))
                                                    )
                                                }
                                                .onEnded { _ in
                                                    activeOverlayResizeDrag = nil
                                                    model.saveOverlays()
                                                }
                                        )
                                }
                            }
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(overlay.kind.title) overlay")
                            .accessibilityValue("Starts \(overlay.startSeconds), ends \(overlay.endSeconds)\(selectedTimelineItem == .overlay(overlay.id) ? ", selected" : "")")
                            .accessibilityHint("Select to edit this overlay. Drag to move it, or use inspector fields for keyboard editing.")
                            .onTapGesture {
                                selectedTimelineItem = .overlay(overlay.id)
                                editorInspectorTab = .overlays
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if activeOverlayDrag?.id != overlay.id {
                                            activeOverlayDrag = OverlayPreviewDragState(
                                                id: overlay.id,
                                                startX: secondsValue(overlay.x) ?? 0,
                                                startY: secondsValue(overlay.y) ?? 0
                                            )
                                        }
                                        guard let drag = activeOverlayDrag, drag.id == overlay.id else { return }
                                        model.updateOverlayFrame(
                                            id: overlay.id,
                                            x: drag.startX + Double(value.translation.width / max(contentFrame.width, 1)),
                                            y: drag.startY + Double(value.translation.height / max(contentFrame.height, 1))
                                        )
                                    }
                                    .onEnded { _ in
                                        activeOverlayDrag = nil
                                        model.saveOverlays()
                                    }
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder var captionPreviewOverlay: some View {
        if model.captionBurnInEnabled, let caption = model.activeCaption(at: model.currentTimeSeconds) {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
                VStack {
                    if model.captionPlacement == .bottom || model.captionPlacement == .middle {
                        Spacer()
                    }
                    Text(caption.text)
                        .font(.system(size: CGFloat(secondsValue(model.captionFontSize) ?? 34), weight: .bold))
                        .foregroundStyle(Color(rgba: model.captionTextColor))
                        .multilineTextAlignment(.center)
                        .lineLimit(model.captionMaxLineCount)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color(rgba: model.captionBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: min(760, max(contentFrame.width - 64, 1)))
                        .padding(.horizontal, 32)
                        .padding(.vertical, max(18, CGFloat((secondsValue(model.captionSafeMargin) ?? 0.07) * Double(contentFrame.height))))
                        .onTapGesture {
                            selectedTimelineItem = .caption(caption.id)
                            editorInspectorTab = .captions
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Caption overlay")
                        .accessibilityValue(caption.text)
                        .accessibilityHint("Select to edit this caption in the Captions panel.")
                    if model.captionPlacement == .top {
                        Spacer()
                    }
                    if model.captionPlacement == .middle {
                        Spacer()
                    }
                }
                .frame(width: contentFrame.width, height: contentFrame.height)
                .position(x: contentFrame.midX, y: contentFrame.midY)
            }
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder func overlayPreview(_ overlay: EditableOverlayRow) -> some View {
        switch overlay.kind {
        case .text:
            Text(overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Title" : overlay.text)
                .font(.system(size: CGFloat(secondsValue(overlay.fontSize) ?? 34), weight: .bold))
                .foregroundStyle(Color(rgba: overlay.textColor))
                .multilineTextAlignment(.center)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(rgba: overlay.fillColor), in: RoundedRectangle(cornerRadius: 8))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .rectangle:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(rgba: overlay.fillColor).opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(rgba: overlay.strokeColor), lineWidth: 3))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .ellipse:
            Ellipse()
                .fill(Color(rgba: overlay.fillColor).opacity(0.22))
                .overlay(Ellipse().stroke(Color(rgba: overlay.strokeColor), lineWidth: 3))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .line, .arrow:
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height * 0.2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.8))
                }
                .stroke(Color(rgba: overlay.strokeColor), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .overlay(alignment: .bottomTrailing) {
                    if overlay.kind == .arrow {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(Color(rgba: overlay.strokeColor))
                            .font(.headline.weight(.bold))
                    }
                }
            }
            .opacity(secondsValue(overlay.opacity) ?? 1)
        case .callout:
            Text(overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Callout" : overlay.text)
                .font(.system(size: CGFloat(secondsValue(overlay.fontSize) ?? 28), weight: .bold))
                .foregroundStyle(Color(rgba: overlay.textColor))
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(rgba: overlay.fillColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(rgba: overlay.strokeColor), lineWidth: 2))
                .opacity(secondsValue(overlay.opacity) ?? 1)
        case .image:
            if let image = model.overlayImage(for: overlay) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .opacity(secondsValue(overlay.opacity) ?? 1)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.1))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        case .highlight:
            highlightPreview(overlay)
        }
    }

    func overlayResizeHandle() -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .accessibilityLabel("Resize overlay")
            .accessibilityHint("Drag to resize the selected overlay. Use Width and Height fields in the inspector for keyboard editing.")
    }

    @ViewBuilder func highlightPreview(_ overlay: EditableOverlayRow) -> some View {
        let opacity = secondsValue(overlay.opacity) ?? 0.6
        let stroke = Color(rgba: overlay.strokeColor)
        let fill = Color(rgba: overlay.fillColor)
        let cornerRadius = CGFloat(secondsValue(overlay.cornerRadius) ?? 12)
        switch overlay.highlightShape {
        case .ellipse:
            Ellipse()
                .fill(fill.opacity(overlay.highlightMode == .outline ? 0.03 : min(opacity, 0.28)))
                .overlay(Ellipse().stroke(stroke, style: StrokeStyle(lineWidth: 3, dash: overlay.highlightMode == .outline ? [] : [7, 4])))
                .shadow(color: stroke.opacity(overlay.highlightMode == .spotlight ? 0.45 : 0), radius: CGFloat(secondsValue(overlay.featherRadius) ?? 0))
        case .rectangle:
            Rectangle()
                .fill(fill.opacity(overlay.highlightMode == .outline ? 0.03 : min(opacity, 0.28)))
                .overlay(Rectangle().stroke(stroke, style: StrokeStyle(lineWidth: 3, dash: overlay.highlightMode == .outline ? [] : [7, 4])))
                .shadow(color: stroke.opacity(overlay.highlightMode == .spotlight ? 0.45 : 0), radius: CGFloat(secondsValue(overlay.featherRadius) ?? 0))
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fill.opacity(overlay.highlightMode == .outline ? 0.03 : min(opacity, 0.28)))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(stroke, style: StrokeStyle(lineWidth: 3, dash: overlay.highlightMode == .outline ? [] : [7, 4])))
                .shadow(color: stroke.opacity(overlay.highlightMode == .spotlight ? 0.45 : 0), radius: CGFloat(secondsValue(overlay.featherRadius) ?? 0))
        }
    }

    func overlayPreviewFrame(_ overlay: EditableOverlayRow, in contentFrame: CGRect) -> CGRect {
        let x = CGFloat(secondsValue(overlay.x) ?? 0)
        let y = CGFloat(secondsValue(overlay.y) ?? 0)
        let width = CGFloat(secondsValue(overlay.width) ?? 0.2)
        let height = CGFloat(secondsValue(overlay.height) ?? 0.15)
        return EditorNormalizedGeometry.topDownFrame(
            for: NormalizedEditRect(
                x: Double(x),
                y: Double(y),
                width: Double(width),
                height: Double(height)
            ),
            in: contentFrame,
            minimumSize: CGSize(width: 20, height: 20)
        )
    }

    @ViewBuilder var cursorPreviewOverlay: some View {
        if model.cursorPreviewMetadata != nil {
            GeometryReader { proxy in
                let contentFrame = previewContentFrame(in: proxy.size)
                ZStack {
                    if model.cursorClickEffectsVisible,
                       let click = model.cursorClick(at: model.currentTimeSeconds) {
                        let point = previewPoint(click.position, in: contentFrame)
                        let progress = model.cursorClickProgress(click, at: model.currentTimeSeconds)
                        let ringSize = CGFloat(36 * model.cursorClickScale * (0.65 + progress))
                        Circle()
                            .stroke(Color(rgba: model.cursorClickColor).opacity(model.cursorClickOpacity * (1 - progress)), lineWidth: 3)
                            .frame(width: ringSize, height: ringSize)
                            .position(point)
                    }

                    if model.cursorPointerVisible,
                       let sample = model.cursorSample(at: model.currentTimeSeconds) {
                        cursorPointerPreview(style: model.cursorPointerStyle)
                            .scaleEffect(model.cursorPointerScale)
                            .position(previewPoint(sample.position, in: contentFrame))
                    }

                    if model.cursorKeyboardVisible,
                       let label = model.keyboardPreviewLabel(at: model.currentTimeSeconds) {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.82 * model.cursorKeyboardOpacity), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                            .position(x: contentFrame.midX, y: max(contentFrame.minY + 32, contentFrame.maxY - 34))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder func cursorPointerPreview(style: EditorCursorPointerStyle) -> some View {
        switch style {
        case .macOS:
            Image(systemName: "cursorarrow")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color(rgba: model.cursorPointerFillColor))
                .shadow(color: Color(rgba: model.cursorPointerStrokeColor).opacity(0.95), radius: 1.6)
        case .touchDot:
            Circle()
                .fill(Color(rgba: model.cursorPointerFillColor).opacity(0.92))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(Color(rgba: model.cursorPointerStrokeColor).opacity(0.95), lineWidth: 2)
                )
        }
    }

    func previewContentFrame(in size: CGSize) -> CGRect {
        EditorNormalizedGeometry.contentFrame(
            in: size,
            padding: model.canvasPreviewPadding,
            aspectRatio: model.canvasPreviewAspectRatio
        )
    }

    func previewPoint(_ point: NormalizedCapturePoint, in frame: CGRect) -> CGPoint {
        EditorNormalizedGeometry.flippedTopDownPoint(for: point, in: frame)
    }

    var selectedZoomID: String? {
        if case .zoom(let id) = selectedTimelineItem {
            return id
        }
        return nil
    }
}
