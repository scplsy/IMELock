import AppKit
import SwiftUI

struct MenuContentView: View {
    let controller: LockController
    let settingsWindow: SettingsWindowPresenter

    var body: some View {
        Text("IMELock · \(controller.status.title)")
        Text("当前：\(controller.currentSource?.name ?? "暂时无法读取")")
        if controller.isEnabled, let target = controller.target {
            Text("锁定目标：\(target.name)")
        }
        if case .paused = controller.status, let detail = controller.status.detail {
            Text(detail)
        }
        Text("锁定已生效：\(controller.restorationCount.formatted()) 次")

        Divider()

        if controller.isEnabled {
            if controller.status.canRetry {
                Button("重试恢复", systemImage: "arrow.clockwise", action: controller.retry)
            }
            Button("解除锁定", systemImage: "lock.open", action: controller.unlock)
        } else {
            Button("锁定当前输入法", systemImage: "lock", action: controller.lockCurrent)
                .disabled(controller.currentSource == nil)
        }

        Divider()
        Button("设置…", action: settingsWindow.show)
            .keyboardShortcut(",", modifiers: .command)
        Button("退出 IMELock") {
            controller.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
