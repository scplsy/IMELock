import Foundation

struct InputSource: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

enum LockFault: String, Codable, Sendable {
    case targetUnavailable
    case restorationFailed
    case frequentChanges
}

struct LockConfiguration: Codable, Equatable, Sendable {
    var target: InputSource?
    var isEnabled = false
    // A fault requires an explicit retry, including after restarting the app.
    var fault: LockFault?
}

enum PauseReason: Equatable, Sendable {
    case secureInput
    case sessionInactive
    case fault(LockFault)
}

enum LockStatus: Equatable, Sendable {
    case unlocked
    case locked
    case paused(PauseReason)
}

struct InputSnapshot: Sendable {
    var current: InputSource?
    var availableIDs: Set<String>
    var isSecureInput = false
    var isSessionActive = true
}

enum SelectionResult: Equatable, Sendable {
    case selected
    case unavailable
    case failed(Int32)
}

/// Pure state machine. Times are monotonic seconds supplied by the caller.
/// A successful API return is only a request; a later observation confirms it.
struct LockEngine {
    static let retryInterval: TimeInterval = 0.15
    static let maximumConsecutiveFailures = 3
    static let contentionWindow: TimeInterval = 2
    static let maximumAttemptsInWindow = 5

    private(set) var configuration: LockConfiguration
    private(set) var status: LockStatus = .unlocked
    private(set) var lastErrorCode: Int32?
    private(set) var restorationCount: Int
    private var attempts: [TimeInterval] = []
    private var lastAttempt: TimeInterval?
    private var pendingAttempt: SelectionAttempt?
    private var consecutiveFailures = 0

    private struct SelectionAttempt {
        let observedDifferentSource: Bool
        var wasAccepted = false
    }

    init(configuration: LockConfiguration = LockConfiguration(), restorationCount: Int = 0) {
        self.configuration = configuration
        self.restorationCount = max(0, restorationCount)
        if configuration.target == nil {
            self.configuration = LockConfiguration()
        }
    }

    mutating func lock(to source: InputSource) {
        configuration = LockConfiguration(target: source, isEnabled: true)
        clearAttempts()
    }

    mutating func unlock() {
        configuration.isEnabled = false
        configuration.fault = nil
        status = .unlocked
        clearAttempts()
    }

    mutating func retry() {
        configuration.fault = nil
        clearAttempts()
    }

    /// Invalidates attempts interrupted by sleep, session changes, or secure input.
    /// A latched fault is intentionally preserved.
    mutating func resetTransientAttempts() {
        clearAttempts()
    }

    mutating func setSessionActive(_ isActive: Bool) {
        clearAttempts()
        if !configuration.isEnabled {
            status = .unlocked
        } else if let fault = configuration.fault {
            status = .paused(.fault(fault))
        } else if !isActive {
            status = .paused(.sessionInactive)
        } else if status == .paused(.sessionInactive) {
            status = .locked // Armed; wait for the next app activation to inspect the source.
        }
    }

    mutating func reconcile(_ snapshot: InputSnapshot, now: TimeInterval, allowsSelection: Bool = true) -> InputSource? {
        guard configuration.isEnabled, let target = configuration.target else {
            status = .unlocked
            return nil
        }
        if let fault = configuration.fault {
            status = .paused(.fault(fault))
            return nil
        }
        guard snapshot.isSessionActive else {
            clearAttempts()
            status = .paused(.sessionInactive)
            return nil
        }
        guard !snapshot.isSecureInput else {
            clearAttempts()
            status = .paused(.secureInput)
            return nil
        }
        guard snapshot.availableIDs.contains(target.id) else {
            pause(with: .targetUnavailable)
            return nil
        }

        status = .locked
        if snapshot.current?.id == target.id {
            // Count only an accepted selection following an observed change,
            // confirmed by the actual source. Repeated notifications add nothing.
            if let pendingAttempt, pendingAttempt.wasAccepted,
               pendingAttempt.observedDifferentSource, restorationCount < Int.max {
                restorationCount += 1
            }
            pendingAttempt = nil
            consecutiveFailures = 0
            lastErrorCode = nil
            return nil
        }

        if !allowsSelection {
            if pendingAttempt != nil {
                pendingAttempt = nil
                consecutiveFailures += 1
            }
            if consecutiveFailures >= Self.maximumConsecutiveFailures {
                pause(with: .restorationFailed)
            }
            return nil
        }

        // Coalesce duplicate notifications and allow the system to finish switching.
        if let lastAttempt, now - lastAttempt < Self.retryInterval {
            return nil
        }
        if pendingAttempt != nil {
            pendingAttempt = nil
            consecutiveFailures += 1
        }
        guard consecutiveFailures < Self.maximumConsecutiveFailures else {
            pause(with: .restorationFailed)
            return nil
        }

        attempts.removeAll { now - $0 >= Self.contentionWindow }
        guard attempts.count < Self.maximumAttemptsInWindow else {
            pause(with: .frequentChanges)
            return nil
        }
        attempts.append(now)
        lastAttempt = now
        pendingAttempt = SelectionAttempt(observedDifferentSource: snapshot.current != nil)
        return target
    }

    mutating func recordSelectionResult(_ result: SelectionResult) {
        guard pendingAttempt != nil else { return }
        switch result {
        case .selected:
            pendingAttempt?.wasAccepted = true // Wait for the actual input source to match.
        case .unavailable:
            pause(with: .targetUnavailable)
        case .failed(let code):
            pendingAttempt = nil
            lastErrorCode = code
            consecutiveFailures += 1
            if consecutiveFailures >= Self.maximumConsecutiveFailures {
                pause(with: .restorationFailed)
            }
        }
    }

    private mutating func pause(with fault: LockFault) {
        configuration.fault = fault
        status = .paused(.fault(fault))
        pendingAttempt = nil
    }

    private mutating func clearAttempts() {
        attempts.removeAll()
        lastAttempt = nil
        pendingAttempt = nil
        consecutiveFailures = 0
        lastErrorCode = nil
    }
}
