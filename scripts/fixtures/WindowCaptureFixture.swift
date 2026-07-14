import AppKit

@main
@MainActor
struct WindowCaptureFixture {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 640, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LessonMeld Window Capture Fixture"
        window.backgroundColor = .systemBlue
        window.orderFrontRegardless()

        application.run()
    }
}
