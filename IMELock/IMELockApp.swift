import SwiftUI

@main
struct IMELockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarPreferences.visibilityKey) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuContentView(controller: appDelegate.controller, settingsWindow: appDelegate.settingsWindow)
                .onAppear(perform: appDelegate.controller.refresh)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: appDelegate.controller.status))
                .renderingMode(.template)
                .accessibilityLabel("IMELock：\(appDelegate.controller.status.title)")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…", action: appDelegate.settingsWindow.show)
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
