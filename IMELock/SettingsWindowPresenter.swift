import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter {
    private let controller: LockController
    private let loginItem: LoginItemManager
    private var window: NSWindow?

    init(controller: LockController, loginItem: LoginItemManager) {
        self.controller = controller
        self.loginItem = loginItem
    }

    func show() {
        controller.refresh()
        loginItem.refresh()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 490, height: 750),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "IMELock 设置"
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller, loginItem: loginItem))
            window.center()
            window.setFrameAutosaveName("IMELockSettings")
            self.window = window
        }

        // Menu tracking must finish before activating the settings window.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
