import AppKit
import AVFoundation
import AVKit
import DMLessonMeldCore
import SwiftUI
import UniformTypeIdentifiers

extension ProjectEditorView {
    func mediaTimelineEditor(manifest: ProjectManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Timeline", systemImage: "timeline.selection")
                    .font(.headline)
                Text(model.formattedCurrentTime)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.stepPlayhead(by: -1)
                } label: {
                    Label("Back 1s", systemImage: "backward.frame")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                Button {
                    model.stepPlayhead(by: 1)
                } label: {
                    Label("Forward 1s", systemImage: "forward.frame")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                Button {
                    model.addCutAtPlayhead()
                    persistTimelineEditChanges(for: .moveCut)
                    editorInspectorTab = .cuts
                } label: {
                    Label("Cut", systemImage: "scissors")
                }
                .keyboardShortcut("b", modifiers: [.option])
                Button {
                    model.addZoomAtPlayhead()
                    persistTimelineEditChanges(for: .moveZoom)
                    editorInspectorTab = .zooms
                } label: {
                    Label("Zoom", systemImage: "plus.magnifyingglass")
                }
                .keyboardShortcut("z", modifiers: [.option])
                Button {
                    model.addAudioVolumeRegionAtPlayhead()
                    persistTimelineEditChanges(for: .moveAudioVolume)
                    editorInspectorTab = .audio
                } label: {
                    Label("Volume", systemImage: "speaker.wave.2")
                }
                .keyboardShortcut("v", modifiers: [.option])
                Button {
                    model.addSpeedRegionAtPlayhead(rate: 2)
                    persistTimelineEditChanges(for: .moveSpeed)
                    editorInspectorTab = .audio
                } label: {
                    Label("Speed", systemImage: "speedometer")
                }
                .keyboardShortcut("s", modifiers: [.option])
                Button {
                    model.addOverlayAtPlayhead(kind: .text)
                    persistTimelineEditChanges(for: .moveOverlay)
                    editorInspectorTab = .overlays
                } label: {
                    Label("Overlay", systemImage: "textformat")
                }
                .keyboardShortcut("t", modifiers: [.option])
                Button {
                    model.addCaptionAtPlayhead()
                    persistTimelineEditChanges(for: .moveCaption)
                    editorInspectorTab = .captions
                } label: {
                    Label("Caption", systemImage: "captions.bubble")
                }
                .keyboardShortcut("c", modifiers: [.option])
                Button {
                    model.addCursorHiddenRangeAtPlayhead()
                    persistTimelineEditChanges(for: .moveCursorHide)
                    editorInspectorTab = .cursor
                } label: {
                    Label("Hide Cursor", systemImage: "cursorarrow.slash")
                }
                .keyboardShortcut("h", modifiers: [.option])
                Button {
                    deleteSelectedTimelineItem()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedTimelineItem == nil)
                Button {
                    model.saveEditDecisions()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                Label("Scale", systemImage: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
                Slider(value: $timelineZoom, in: 1...6)
                    .frame(width: 120)
                    .accessibilityLabel("Timeline scale")
                    .accessibilityValue(String(format: "%.1fx", timelineZoom))
            }
            if !model.editValidationIssues.isEmpty {
                Text(model.editValidationIssues.map(\.message).joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            GeometryReader { proxy in
                let duration = editorTimelineDuration
                let timelineWidth = max(proxy.size.width, proxy.size.width * CGFloat(timelineZoom))
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 8) {
                        timelineRuler(width: timelineWidth, duration: duration)
                        timelineLane(
                            title: "Clip",
                            tint: .yellow,
                            width: timelineWidth,
                            duration: duration,
                            height: 38
                        ) {
                            clipTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Audio",
                            tint: .teal,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            audioTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Speed",
                            tint: .indigo,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            speedTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Cuts",
                            tint: .red,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            cutTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Zooms",
                            tint: .purple,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            zoomTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Overlays",
                            tint: .green,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            overlayTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Captions",
                            tint: .mint,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            captionTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Camera",
                            tint: .orange,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            cameraTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Cursor",
                            tint: .cyan,
                            width: timelineWidth,
                            duration: duration,
                            height: 30
                        ) {
                            cursorTimelineContent(width: timelineWidth, duration: duration)
                        }
                        timelineLane(
                            title: "Markers",
                            tint: .blue,
                            width: timelineWidth,
                            duration: duration,
                            height: 26
                        ) {
                            markerTimelineContent(width: timelineWidth, duration: duration)
                        }
                    }
                    .frame(width: timelineWidth, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        playheadLine(width: timelineWidth, duration: duration)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard activeTimelineDrag == nil else { return }
                                model.seek(to: timelineSeconds(value.location.x, width: timelineWidth, duration: duration))
                            }
                    )
                }
            }
        }
        .padding(.top, 12)
        .focusable()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video timeline")
        .accessibilityHint("Use Left and Right Arrow to move the playhead. Use Delete to remove the selected timeline item.")
        .onMoveCommand { direction in
            switch direction {
            case .left:
                model.stepPlayhead(by: -1)
            case .right:
                model.stepPlayhead(by: 1)
            default:
                break
            }
        }
        .onDeleteCommand {
            deleteSelectedTimelineItem()
        }
    }

    var editorTimelineDuration: Double {
        max(model.previewDurationSeconds, secondsValue(model.sourceDurationSeconds) ?? 0, 1)
    }

    func timelineRuler(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...6, id: \.self) { tick in
                let ratio = CGFloat(tick) / 6
                let seconds = duration * Double(ratio)
                let x = timelineTrackInset + max(0, width - timelineTrackInset) * ratio
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 1, height: 8)
                    Text(formatSeconds(seconds))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .offset(x: max(0, min(width - 48, x)))
            }
        }
        .frame(width: width, height: 24, alignment: .topLeading)
    }

    func timelineLane<Content: View>(
        title: String,
        tint: Color,
        width: CGFloat,
        duration: Double,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                )
            content()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) timeline lane")
        .accessibilityHint("Contains editable \(title.lowercased()) regions.")
    }

    func clipTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            let trimStart = secondsValue(model.trimStartSeconds) ?? 0
            let trimEnd = secondsValue(model.trimEndSeconds) ?? duration
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.yellow.opacity(0.36))
                .frame(width: max(0, width - timelineTrackInset))
                .offset(x: timelineTrackInset)
            if let trimStart = secondsValue(model.trimStartSeconds), trimStart > 0 {
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: max(0, timelineX(trimStart, width: width, duration: duration) - timelineTrackInset))
                    .offset(x: timelineTrackInset)
            }
            if let trimEnd = secondsValue(model.trimEndSeconds), trimEnd < duration {
                let x = timelineX(trimEnd, width: width, duration: duration)
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(width: max(0, width - x))
                    .offset(x: x)
            }
            Text("Clip  \(formatSeconds(duration))")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, max(timelineTrackInset + 10, width * 0.46))
            trimHandle("In")
                .offset(x: timelineX(trimStart, width: width, duration: duration) - 5)
                .gesture(timelineDragGesture(action: .trimStart, id: "trim-start", start: trimStart, end: trimEnd, width: width, duration: duration))
                .help("Drag to set trim start")
                .accessibilityLabel("Trim start handle")
                .accessibilityValue(formatSeconds(trimStart))
                .accessibilityHint("Drag to set trim start, or press Option I to set it to the playhead.")
            trimHandle("Out")
                .offset(x: timelineX(trimEnd, width: width, duration: duration) - 5)
                .gesture(timelineDragGesture(action: .trimEnd, id: "trim-end", start: trimStart, end: trimEnd, width: width, duration: duration))
                .help("Drag to set trim end")
                .accessibilityLabel("Trim end handle")
                .accessibilityValue(formatSeconds(trimEnd))
                .accessibilityHint("Drag to set trim end, or press Option O to set it to the playhead.")
        }
        .contextMenu {
            Button("Set Trim In to Playhead") {
                model.setTrimStartToPlayhead()
                persistTimelineEditChanges(for: .trimStart)
            }
            Button("Set Trim Out to Playhead") {
                model.setTrimEndToPlayhead()
                persistTimelineEditChanges(for: .trimEnd)
            }
            Button("Clear Trim") {
                model.clearTrim(duration: duration)
                persistTimelineEditChanges(for: .trimStart)
            }
        }
    }

    func cutTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.cutRows) { cut in
                if let start = secondsValue(cut.startSeconds), let end = secondsValue(cut.endSeconds), end > start {
                    timelineBlock(
                        title: cut.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cut" : cut.reason,
                        tint: .red,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: cut.isEnabled,
                        isSelected: selectedTimelineItem == .cut(cut.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .cut(cut.id)
                        editorInspectorTab = .cuts
                    }
                    .gesture(timelineDragGesture(action: .moveCut, id: cut.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCutStart, id: cut.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCutEnd, id: cut.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Cut") {
                            model.seek(to: start)
                        }
                        Button(cut.isEnabled ? "Disable Cut" : "Enable Cut") {
                            model.toggleCutEnabled(id: cut.id)
                            persistTimelineEditChanges(for: .moveCut)
                        }
                        Button("Duplicate Cut") {
                            model.duplicateCut(id: cut.id, duration: duration)
                            persistTimelineEditChanges(for: .moveCut)
                        }
                        Button("Remove Cut", role: .destructive) {
                            model.removeCut(id: cut.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveCut)
                        }
                    }
                }
            }
        }
    }

    func audioTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            if let start = secondsValue(model.backgroundMusicStart) {
                let musicDuration = secondsValue(model.backgroundMusicDuration) ?? max(0, duration - start)
                let end = min(duration, start + max(0.1, musicDuration))
                if !model.backgroundMusicPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, end > start {
                    timelineBlock(
                        title: "Music",
                        tint: .teal,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: false
                    )
                    .opacity(0.72)
                }
            }
            ForEach(model.audioVolumeRows) { region in
                if let start = secondsValue(region.startSeconds), let end = secondsValue(region.endSeconds), end > start {
                    timelineBlock(
                        title: "\(region.track.title) \(region.gain)x",
                        tint: .teal,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: region.isEnabled,
                        isSelected: selectedTimelineItem == .audioVolume(region.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .audioVolume(region.id)
                        editorInspectorTab = .audio
                    }
                    .gesture(timelineDragGesture(action: .moveAudioVolume, id: region.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeAudioVolumeStart, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeAudioVolumeEnd, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Volume Region") {
                            model.seek(to: start)
                        }
                        Button(region.isEnabled ? "Disable Region" : "Enable Region") {
                            model.toggleAudioVolumeRegionEnabled(id: region.id)
                            persistTimelineEditChanges(for: .moveAudioVolume)
                        }
                        Button("Remove Region", role: .destructive) {
                            model.removeAudioVolumeRegion(id: region.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveAudioVolume)
                        }
                    }
                }
            }
        }
    }

    func speedTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.speedRows) { speed in
                if let start = secondsValue(speed.startSeconds), let end = secondsValue(speed.endSeconds), end > start {
                    timelineBlock(
                        title: "\(speed.playbackRate)x",
                        tint: .indigo,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: selectedTimelineItem == .speed(speed.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .speed(speed.id)
                        editorInspectorTab = .audio
                    }
                    .gesture(timelineDragGesture(action: .moveSpeed, id: speed.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeSpeedStart, id: speed.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeSpeedEnd, id: speed.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Speed Region") {
                            model.seek(to: start)
                        }
                        Button("Remove Region", role: .destructive) {
                            model.removeSpeedRegion(id: speed.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveSpeed)
                        }
                    }
                }
            }
        }
    }

    func zoomTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.zoomRows) { zoom in
                if let start = secondsValue(zoom.startSeconds), let end = secondsValue(zoom.endSeconds), end > start {
                    timelineBlock(
                        title: "Zoom \(zoom.scale)x",
                        tint: .purple,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: zoom.isEnabled,
                        isSelected: selectedTimelineItem == .zoom(zoom.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .zoom(zoom.id)
                        editorInspectorTab = .zooms
                    }
                    .gesture(timelineDragGesture(action: .moveZoom, id: zoom.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeZoomStart, id: zoom.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeZoomEnd, id: zoom.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Zoom") {
                            model.seek(to: start)
                        }
                        Button(zoom.isEnabled ? "Disable Zoom" : "Enable Zoom") {
                            model.toggleZoomEnabled(id: zoom.id)
                            persistTimelineEditChanges(for: .moveZoom)
                        }
                        Button("Duplicate Zoom") {
                            model.duplicateZoom(id: zoom.id, duration: duration)
                            persistTimelineEditChanges(for: .moveZoom)
                        }
                        Button("Remove Zoom", role: .destructive) {
                            model.removeZoom(id: zoom.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveZoom)
                        }
                    }
                }
            }
        }
    }

    func overlayTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.overlayRows) { overlay in
                if let start = secondsValue(overlay.startSeconds), let end = secondsValue(overlay.endSeconds), end > start {
                    timelineBlock(
                        title: overlay.kind.title,
                        tint: .green,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: overlay.isEnabled,
                        isSelected: selectedTimelineItem == .overlay(overlay.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .overlay(overlay.id)
                        editorInspectorTab = .overlays
                    }
                    .gesture(timelineDragGesture(action: .moveOverlay, id: overlay.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeOverlayStart, id: overlay.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeOverlayEnd, id: overlay.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Overlay") {
                            model.seek(to: start)
                        }
                        Button(overlay.isEnabled ? "Disable Overlay" : "Enable Overlay") {
                            model.toggleOverlayEnabled(id: overlay.id)
                            persistTimelineEditChanges(for: .moveOverlay)
                        }
                        Button("Remove Overlay", role: .destructive) {
                            model.removeOverlay(id: overlay.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveOverlay)
                        }
                    }
                }
            }
        }
    }

    func captionTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.captionRows) { caption in
                if let start = secondsValue(caption.startSeconds), let end = secondsValue(caption.endSeconds), end > start {
                    timelineBlock(
                        title: caption.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Caption" : caption.text,
                        tint: .mint,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: selectedTimelineItem == .caption(caption.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .caption(caption.id)
                        editorInspectorTab = .captions
                    }
                    .gesture(timelineDragGesture(action: .moveCaption, id: caption.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCaptionStart, id: caption.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCaptionEnd, id: caption.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Caption") {
                            model.seek(to: start)
                        }
                        Button("Remove Caption", role: .destructive) {
                            model.removeCaption(id: caption.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveCaption)
                        }
                    }
                }
            }
        }
    }

    func cameraTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.cameraRegionRows) { region in
                if let start = secondsValue(region.startSeconds), let end = secondsValue(region.endSeconds), end > start {
                    timelineBlock(
                        title: region.preset.title,
                        tint: .orange,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: region.isEnabled,
                        isSelected: selectedTimelineItem == .cameraRegion(region.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .cameraRegion(region.id)
                        editorInspectorTab = .camera
                    }
                    .gesture(timelineDragGesture(action: .moveCameraRegion, id: region.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCameraRegionStart, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCameraRegionEnd, id: region.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Camera Region") {
                            model.seek(to: start)
                        }
                        Button(region.isEnabled ? "Disable Region" : "Enable Region") {
                            model.toggleCameraRegionEnabled(id: region.id)
                            persistTimelineEditChanges(for: .moveCameraRegion)
                        }
                        Button("Remove Region", role: .destructive) {
                            model.removeCameraRegion(id: region.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveCameraRegion)
                        }
                    }
                }
            }
        }
    }

    func cursorTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.cursorHiddenRangeRows) { range in
                if let start = secondsValue(range.startSeconds), let end = secondsValue(range.endSeconds), end > start {
                    timelineBlock(
                        title: "Hide pointer",
                        tint: .cyan,
                        start: start,
                        end: end,
                        width: width,
                        duration: duration,
                        height: 22,
                        isEnabled: true,
                        isSelected: selectedTimelineItem == .cursorHide(range.id)
                    )
                    .onTapGesture {
                        selectedTimelineItem = .cursorHide(range.id)
                        editorInspectorTab = .cursor
                    }
                    .gesture(timelineDragGesture(action: .moveCursorHide, id: range.id, start: start, end: end, width: width, duration: duration))
                    .overlay(alignment: .leading) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCursorHideStart, id: range.id, start: start, end: end, width: width, duration: duration))
                    }
                    .overlay(alignment: .trailing) {
                        timelineResizeHandle()
                            .gesture(timelineDragGesture(action: .resizeCursorHideEnd, id: range.id, start: start, end: end, width: width, duration: duration))
                    }
                    .contextMenu {
                        Button("Jump to Range") {
                            model.seek(to: start)
                        }
                        Button("Remove Range", role: .destructive) {
                            model.removeCursorHiddenRange(id: range.id)
                            selectedTimelineItem = nil
                            model.saveEditorSettings()
                        }
                    }
                }
            }
        }
    }

    func markerTimelineContent(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .leading) {
            ForEach(model.markerRows) { marker in
                if let seconds = secondsValue(marker.timeSeconds) {
                    let x = timelineX(seconds, width: width, duration: duration)
                    VStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                        Text(marker.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.blue)
                    .frame(width: 86, alignment: .leading)
                    .offset(x: max(76, min(width - 86, x)))
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill((selectedTimelineItem == .marker(marker.id) ? Color.blue.opacity(0.22) : Color.clear))
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(marker.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timeline marker" : marker.title)
                    .accessibilityValue("\(formatSeconds(seconds))\(selectedTimelineItem == .marker(marker.id) ? ", Selected" : "")")
                    .accessibilityHint("Select to edit this marker. Use the context menu to jump, duplicate, or remove it.")
                    .onTapGesture {
                        selectedTimelineItem = .marker(marker.id)
                    }
                    .gesture(timelineDragGesture(action: .moveMarker, id: marker.id, start: seconds, end: seconds, width: width, duration: duration))
                    .contextMenu {
                        Button("Jump to Marker") {
                            model.seek(to: seconds)
                        }
                        Button("Duplicate Marker") {
                            model.duplicateMarker(id: marker.id, duration: duration)
                            persistTimelineEditChanges(for: .moveMarker)
                        }
                        Button("Remove Marker", role: .destructive) {
                            model.removeMarker(id: marker.id)
                            selectedTimelineItem = nil
                            persistTimelineEditChanges(for: .moveMarker)
                        }
                    }
                }
            }
        }
    }

    func timelineBlock(
        title: String,
        tint: Color,
        start: Double,
        end: Double,
        width: CGFloat,
        duration: Double,
        height: CGFloat,
        isEnabled: Bool,
        isSelected: Bool
    ) -> some View {
        let x = timelineX(start, width: width, duration: duration)
        let blockWidth = max(18, timelineX(end, width: width, duration: duration) - x)
        return Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: blockWidth, height: height, alignment: .leading)
            .background(tint.opacity(isEnabled ? 0.78 : 0.28), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : tint.opacity(isEnabled ? 0.9 : 0.4), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(.white)
            .offset(x: x)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) timeline item")
            .accessibilityValue(timelineItemAccessibilityValue(start: start, end: end, isEnabled: isEnabled, isSelected: isSelected))
            .accessibilityHint("Select to edit. Use the context menu for jump, enable, duplicate, or remove actions where available.")
    }

    func playheadLine(width: CGFloat, duration: Double) -> some View {
        let x = timelineX(model.currentTimeSeconds, width: width, duration: duration)
        return VStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 292)
        }
        .offset(x: x)
    }

    func trimHandle(_ title: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.94))
                .frame(width: 10, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.black.opacity(0.25), lineWidth: 1)
                )
        }
        .foregroundStyle(.black.opacity(0.75))
        .frame(width: 28, height: 38)
        .contentShape(Rectangle())
    }

    func timelineResizeHandle() -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.88))
            .frame(width: 9)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.black.opacity(0.22), lineWidth: 1)
            )
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .accessibilityLabel("Resize timeline item")
            .accessibilityHint("Drag horizontally to adjust this item's start or end time.")
    }

    func timelineItemAccessibilityValue(start: Double, end: Double, isEnabled: Bool, isSelected: Bool) -> String {
        var parts = [
            "\(formatSeconds(start)) to \(formatSeconds(end))",
            isEnabled ? "Enabled" : "Disabled"
        ]
        if isSelected {
            parts.append("Selected")
        }
        return parts.joined(separator: ", ")
    }

    func timelineDragGesture(
        action: TimelineDragAction,
        id: String,
        start: Double,
        end: Double,
        width: CGFloat,
        duration: Double
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeTimelineDrag == nil {
                    activeTimelineDrag = TimelineDragState(
                        action: action,
                        id: id,
                        startSeconds: start,
                        endSeconds: end
                    )
                }
                guard let drag = activeTimelineDrag,
                      drag.action == action,
                      drag.id == id else {
                    return
                }
                applyTimelineDrag(drag, delta: timelineDeltaSeconds(value.translation.width, width: width, duration: duration), duration: duration)
            }
            .onEnded { _ in
                activeTimelineDrag = nil
                persistTimelineEditChanges(for: action)
            }
    }

    func applyTimelineDrag(_ drag: TimelineDragState, delta: Double, duration: Double) {
        switch drag.action {
        case .trimStart:
            model.updateTrimStart(drag.startSeconds + delta, duration: duration)
        case .trimEnd:
            model.updateTrimEnd(drag.endSeconds + delta, duration: duration)
        case .moveCut:
            model.moveCut(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCutStart:
            model.resizeCut(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCutEnd:
            model.resizeCut(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveSpeed:
            model.moveSpeedRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeSpeedStart:
            model.resizeSpeedRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeSpeedEnd:
            model.resizeSpeedRegion(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveAudioVolume:
            model.moveAudioVolumeRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeAudioVolumeStart:
            model.resizeAudioVolumeRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeAudioVolumeEnd:
            model.resizeAudioVolumeRegion(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveZoom:
            model.moveZoom(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeZoomStart:
            model.resizeZoom(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeZoomEnd:
            model.resizeZoom(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveOverlay:
            model.moveOverlay(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeOverlayStart:
            model.resizeOverlay(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeOverlayEnd:
            model.resizeOverlay(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveCaption:
            model.moveCaption(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCaptionStart:
            model.resizeCaption(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCaptionEnd:
            model.resizeCaption(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveCameraRegion:
            model.moveCameraRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCameraRegionStart:
            model.resizeCameraRegion(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCameraRegionEnd:
            model.resizeCameraRegion(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveCursorHide:
            model.moveCursorHiddenRange(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds + delta, duration: duration)
        case .resizeCursorHideStart:
            model.resizeCursorHiddenRange(id: drag.id, start: drag.startSeconds + delta, end: drag.endSeconds, duration: duration)
        case .resizeCursorHideEnd:
            model.resizeCursorHiddenRange(id: drag.id, start: drag.startSeconds, end: drag.endSeconds + delta, duration: duration)
        case .moveMarker:
            model.moveMarker(id: drag.id, to: drag.startSeconds + delta, duration: duration)
        }
    }

    func persistTimelineEditChanges(for action: TimelineDragAction) {
        switch action {
        case .moveMarker:
            model.saveMarkers()
        case .moveOverlay, .resizeOverlayStart, .resizeOverlayEnd:
            model.saveOverlays()
        case .moveCaption, .resizeCaptionStart, .resizeCaptionEnd:
            model.saveCaptions()
        case .moveAudioVolume, .resizeAudioVolumeStart, .resizeAudioVolumeEnd:
            model.saveEditorSettings()
        case .moveCameraRegion, .resizeCameraRegionStart, .resizeCameraRegionEnd:
            model.saveEditorSettings()
        case .moveCursorHide, .resizeCursorHideStart, .resizeCursorHideEnd:
            model.saveEditorSettings()
        case .moveSpeed, .resizeSpeedStart, .resizeSpeedEnd:
            model.saveEditDecisions()
        default:
            model.saveEditDecisions()
        }
    }

    func deleteSelectedTimelineItem() {
        guard let selectedTimelineItem else { return }
        switch selectedTimelineItem {
        case .cut(let id):
            model.removeCut(id: id)
            persistTimelineEditChanges(for: .moveCut)
        case .speed(let id):
            model.removeSpeedRegion(id: id)
            persistTimelineEditChanges(for: .moveSpeed)
        case .audioVolume(let id):
            model.removeAudioVolumeRegion(id: id)
            persistTimelineEditChanges(for: .moveAudioVolume)
        case .zoom(let id):
            model.removeZoom(id: id)
            persistTimelineEditChanges(for: .moveZoom)
        case .overlay(let id):
            model.removeOverlay(id: id)
            persistTimelineEditChanges(for: .moveOverlay)
        case .caption(let id):
            model.removeCaption(id: id)
            persistTimelineEditChanges(for: .moveCaption)
        case .cameraRegion(let id):
            model.removeCameraRegion(id: id)
            persistTimelineEditChanges(for: .moveCameraRegion)
        case .cursorHide(let id):
            model.removeCursorHiddenRange(id: id)
            persistTimelineEditChanges(for: .moveCursorHide)
        case .marker(let id):
            model.removeMarker(id: id)
            persistTimelineEditChanges(for: .moveMarker)
        }
        self.selectedTimelineItem = nil
    }

    func timelineX(_ seconds: Double, width: CGFloat, duration: Double) -> CGFloat {
        guard duration > 0 else { return 0 }
        let trackWidth = max(0, width - timelineTrackInset)
        return timelineTrackInset + min(max(0, CGFloat(seconds / duration) * trackWidth), trackWidth)
    }

    func timelineSeconds(_ x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let trackWidth = max(1, width - timelineTrackInset)
        let trackX = min(max(0, x - timelineTrackInset), trackWidth)
        return Double(trackX / trackWidth) * duration
    }

    func timelineDeltaSeconds(_ translation: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        let trackWidth = max(1, width - timelineTrackInset)
        return Double(translation / trackWidth) * duration
    }

    var timelineTrackInset: CGFloat { 76 }
}
