import AppKit
import SwiftUI

extension View {
    func disablesWindowRestoration() -> some View {
        background(WindowRestorationDisabler())
    }

    func hidesWindowTitle() -> some View {
        background(WindowTitleHider())
    }

    func confirmsWindowClose(_ shouldClose: @escaping () -> Bool) -> some View {
        background(WindowCloseConfirmer(shouldClose: shouldClose))
    }
}

private struct WindowRestorationDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isRestorable = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.isRestorable = false
        }
    }
}

private struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            Self.apply(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.apply(to: nsView.window)
        }
    }

    private static func apply(to window: NSWindow?) {
        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = false
    }
}

private struct WindowCloseConfirmer: NSViewRepresentable {
    var shouldClose: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldClose: shouldClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.shouldClose = shouldClose
            view.window?.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.shouldClose = shouldClose
            nsView.window?.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldClose()
        }
    }
}
