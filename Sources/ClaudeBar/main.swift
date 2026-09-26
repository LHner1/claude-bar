import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        let controller = StatusItemController(model: model)
        self.controller = controller
        // For testing: `open ClaudeBar.app --args --show-popup`
        if CommandLine.arguments.contains("--show-popup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { controller.openPanel() }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
