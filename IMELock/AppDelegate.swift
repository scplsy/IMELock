import AppKit
import Carbon.HIToolbox

enum MenuBarPreferences {
    static let visibilityKey = "showMenuBarIcon"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = LockController()
    let loginItem = LoginItemManager()
    lazy var settingsWindow = SettingsWindowPresenter(controller: controller, loginItem: loginItem)

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(openApplication(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenApplication)
        )
    }

    @objc private func openApplication(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard UserDefaults.standard.object(forKey: MenuBarPreferences.visibilityKey) as? Bool == false,
              event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem
        else { return }
        // Only an explicit open event presents settings. Background launches
        // without this event (including login) remain silent.
        settingsWindow.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
