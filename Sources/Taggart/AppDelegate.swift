import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run as a bare executable (`swift run`) rather than an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Files opened from Finder ("Open With", or dropped on the Dock icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        controller.add(urls)
        controller.showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.shouldTerminate(sender)
    }
}
