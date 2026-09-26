import AppKit
import SwiftUI

/// NSHostingView that reports size changes and can let clicks through to the status button.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?
    var passesClicks = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesClicks ? nil : super.hitTest(point)
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange?() }
    }
}

/// Borderless popup below the status item, like Stats (no popover arrow).
private final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let label: PassthroughHostingView<MenuBarLabel>
    private let panel: PopupPanel
    private let content: PassthroughHostingView<PopupView>
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        label = PassthroughHostingView(rootView: MenuBarLabel(model: model))
        content = PassthroughHostingView(rootView: PopupView(model: model))
        panel = PopupPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: true)
        super.init()
        setUpStatusItem()
        setUpPanel()
        model.closePopup = { [weak self] in self?.closePanel() }
    }

    private func setUpStatusItem() {
        guard let button = statusItem.button else { return }
        label.passesClicks = true
        label.onSizeChange = { [weak self] in self?.layoutLabel() }
        button.addSubview(label)
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Claude Code")
        layoutLabel()
    }

    private func layoutLabel() {
        guard let button = statusItem.button else { return }
        let size = label.fittingSize
        statusItem.length = size.width
        label.frame = NSRect(x: 0, y: (button.bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    private func setUpPanel() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        content.autoresizingMask = [.width, .height]
        content.onSizeChange = { [weak self] in self?.resizePanel() }
        effect.addSubview(content)
        panel.contentView = effect
    }

    @objc private func togglePanel() {
        panel.isVisible ? closePanel() : openPanel()
    }

    func openPanel() {
        model.refreshSessions()
        model.refreshLimits()
        model.refreshUsage()
        resizePanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.highlight(true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Esc
                MainActor.assumeIsolated { self?.closePanel() }
                return nil
            }
            return event
        }
    }

    private func closePanel() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        clickMonitor = nil
        keyMonitor = nil
    }

    /// Fits the panel to its content while keeping the top edge anchored below the status item.
    private func resizePanel() {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let size = content.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = min(anchor.minY - 5, visible.maxY)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}
