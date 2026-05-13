import AppKit
import SwiftUI

@MainActor
final class RegionSelectionWindow: NSPanel {
    private var onCancel: () -> Void

    init(screen: NSScreen, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        hasShadow = false
        contentView = NSHostingView(rootView: RegionSelectionOverlayView(
            screenFrame: screen.frame,
            onComplete: { [weak self] rect in
                self?.close()
                onComplete(rect)
            },
            onCancel: { [weak self] in
                self?.close()
                onCancel()
            }
        ))
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct RegionSelectionOverlayView: View {
    var screenFrame: CGRect
    var onComplete: (CGRect) -> Void
    var onCancel: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.dashed")
                    Text("Drag to select the recording area")
                        .font(.system(size: 15, weight: .semibold))
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 28)

                Text("Release to use the selected region. Press Escape to cancel.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
            }

            if let selectionRect {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .foregroundStyle(Color.white.opacity(0.92))
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(Int(selectionRect.width)) x \(Int(selectionRect.height))")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if startPoint == nil {
                        startPoint = value.startLocation
                    }
                    currentPoint = value.location
                }
                .onEnded { value in
                    let localRect = Self.normalizedRect(from: value.startLocation, to: value.location)
                    guard localRect.width >= 24, localRect.height >= 24 else {
                        startPoint = nil
                        currentPoint = nil
                        return
                    }
                    onComplete(appKitRect(from: localRect))
                }
        )
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return Self.normalizedRect(from: startPoint, to: currentPoint)
    }

    private func appKitRect(from localRect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + localRect.minX,
            y: screenFrame.maxY - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        ).standardized
    }

    private static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).standardized
    }
}
