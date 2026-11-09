import Foundation

extension LockStatus {
    var title: String {
        switch self {
        case .unlocked: "未锁定"
        case .locked: "已锁定"
        case .paused: "已暂停"
        }
    }

    var symbol: String {
        switch self {
        case .unlocked: "lock.open"
        case .locked: "lock.fill"
        case .paused: "pause.circle.fill"
        }
    }

    var detail: String? {
        switch self {
        case .unlocked, .locked:
            nil
        case .paused(.secureInput):
            "安全输入期间暂停，结束后切换应用时继续检查。"
        case .paused(.sessionInactive):
            "屏幕或会话未激活，返回后切换应用时继续检查。"
        case .paused(.fault(.targetUnavailable)):
            "目标输入法不可用，请重新启用后重试。"
        case .paused(.fault(.restorationFailed)):
            "连续恢复失败，请检查输入法后重试。"
        case .paused(.fault(.frequentChanges)):
            "输入法被频繁切换，已暂停以避免持续争抢。"
        }
    }

    var canRetry: Bool {
        switch self {
        case .paused(.fault), .paused(.secureInput): true
        default: false
        }
    }
}
