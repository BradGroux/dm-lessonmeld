import AppKit
import SwiftUI

extension View {
    func disablesWindowRestoration() -> some View {
        background(WindowRestorationDisabler())
    }

    func hidesWindowTitle() -> some View {
        background(WindowTitleHider())
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
