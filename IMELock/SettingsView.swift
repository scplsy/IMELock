import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(MenuBarPreferences.visibilityKey) private var showMenuBarIcon = true

    let controller: LockController
    let loginItem: LoginItemManager

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: controller.status.symbol)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(statusColor)
                        .frame(width: 44, height: 44)
                        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(controller.status.title)
                            .font(.headline)
                        if let detail = controller.status.detail {
                            Text(detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
                LabeledContent("当前输入法", value: controller.currentSource?.name ?? "暂时无法读取")
                if controller.isEnabled, let target = controller.target {
                    LabeledContent("锁定目标", value: target.name)
                }
                if let code = controller.lastErrorCode {
                    LabeledContent("系统返回码", value: String(code))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if controller.isEnabled {
                        if controller.status.canRetry {
                            Button("重试恢复", action: controller.retry)
                        }
                        Button("解除锁定", action: controller.unlock)
                    } else {
                        Button("锁定当前输入法", action: controller.lockCurrent)
                            .disabled(controller.currentSource == nil)
                    }
                }
            } header: {
                Text("输入法锁定")
            }

            Section {
                DelaySettingView(milliseconds: Binding(
                    get: { controller.activationDelayMilliseconds },
                    set: { controller.setActivationDelayMilliseconds($0) }
                ))
            } header: {
                Text("检测延迟")
            } footer: {
                Text("切换应用后，延迟指定时长再检测输入法是否被系统切换")
            }

            Section {
                LabeledContent("累计生效", value: "\(controller.restorationCount.formatted()) 次")
            } header: {
                Text("锁定统计")
            }

            Section {
                Toggle("在菜单栏显示", isOn: $showMenuBarIcon)
                Toggle("登录时启动 IMELock", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                ))
                .disabled(loginItem.isUpdating)
                if loginItem.status == .requiresApproval {
                    Text("请在系统设置的登录项中允许 IMELock。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("打开登录项设置", action: loginItem.openSystemSettings)
                }
                if let error = loginItem.errorMessage {
                    Text("无法更新登录项：\(error)")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } header: {
                Text("通用")
            }

            HStack {
                Text("IMELock \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 490, height: 750)
        .onAppear {
            controller.refresh()
            loginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .locked: .green
        case .unlocked: .secondary
        case .paused: .orange
        }
    }
}
