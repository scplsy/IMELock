import AppKit
import Carbon

private enum ProbeError: Error {
    case failed(String)
}

@MainActor
private final class SimulatedInputSourceService: InputSourceProviding {
    let target = InputSource(id: "test.target", name: "Target")
    let alternate = InputSource(id: "test.alternate", name: "Alternate")
    var source = InputSource(id: "test.target", name: "Target")
    var secureInput = false
    var ignoreSelection = false
    var currentQueries = 0
    var availableQueries = 0
    var secureQueries = 0
    var selections = 0

    func current() -> InputSource? {
        currentQueries += 1
        return source
    }

    func available() -> [InputSource] {
        availableQueries += 1
        return [target, alternate]
    }

    var isSecureInputEnabled: Bool {
        secureQueries += 1
        return secureInput
    }

    func select(_ id: String) -> SelectionResult {
        selections += 1
        if !ignoreSelection { source = id == target.id ? target : alternate }
        return .selected
    }

    func resetQueries() {
        currentQueries = 0
        availableQueries = 0
        secureQueries = 0
        selections = 0
    }

    var totalQueries: Int { currentQueries + availableQueries + secureQueries + selections }
}

@main
@MainActor
struct IntegrationProbe {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let success = await run()
            exit(success ? 0 : 1)
        }
        app.run()
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ProbeError.failed(message) }
    }

    static func waitFor(_ message: String, timeout: TimeInterval = 0.5, _ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !predicate() {
            try require(ProcessInfo.processInfo.systemUptime < deadline, message)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func run() async -> Bool {
        if CommandLine.arguments.contains("--simulated-only") {
            do {
                try await verifyActivationPolicy()
                return true
            } catch {
                print("FAIL: \(error)")
                return false
            }
        }
        let service = InputSourceService()
        guard !service.isSecureInputEnabled, let original = service.current() else {
            print("SKIP: secure input is active or the current input source cannot be read.")
            return false
        }
        var temporarilyEnabled: [TISInputSource] = []
        defer {
            for source in temporarilyEnabled.reversed() { TISDisableInputSource(source) }
        }
        if CommandLine.arguments.contains("--include-system-pinyin") {
            for id in ["com.apple.inputmethod.SCIM", "com.apple.inputmethod.SCIM.ITABC",
                       "com.apple.inputmethod.TCIM", "com.apple.inputmethod.TCIM.Pinyin"] {
                let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
                guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue(),
                      let source = ((list as NSArray) as? [TISInputSource])?.first,
                      let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
                    print("FAIL: system input source unavailable: \(id)")
                    return false
                }
                let enabled = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
                if !enabled {
                    guard TISEnableInputSource(source) == noErr else {
                        print("FAIL: cannot temporarily enable \(id)")
                        return false
                    }
                    temporarilyEnabled.append(source)
                }
            }
        }
        let sources = service.available()
        guard sources.count >= 2 else {
            print("SKIP: at least two enabled keyboard input sources are required.")
            return false
        }
        let suite = "app.imelock.IntegrationProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return false }
        let store = ConfigurationStore(defaults: defaults)
        let events = NotificationCenter()
        var controller = LockController(store: store, workspaceNotifications: events)
        var ownsSecureInput = false
        let originalApplication = NSWorkspace.shared.frontmostApplication
        defer {
            if ownsSecureInput { DisableSecureEventInput() }
            controller.stop()
            _ = service.select(original.id)
            defaults.removePersistentDomain(forName: suite)
            originalApplication?.activate()
        }

        do {
            try await verifyActivationPolicy()
            print("Runtime sources: \(sources.map { "\($0.name) [\($0.id)]" }.joined(separator: ", "))")
            try require(controller.status == .unlocked, "First launch must be unlocked")
            try require(controller.restorationCount == 0, "First launch must start with zero restorations")
            for target in sources {
                let other = sources.first { $0.id != target.id }!
                _ = service.select(target.id)
                try await waitFor("Could not select target", timeout: 1) { service.current()?.id == target.id }
                let countBeforeLock = controller.restorationCount
                controller.lockCurrent()
                try require(controller.target == target, "Locked the wrong target")
                try require(controller.restorationCount == countBeforeLock, "Locking the current source changed statistics")
                for round in 1...3 {
                    let countBeforeRecovery = controller.restorationCount
                    try require(service.select(other.id) == .selected, "External switch failed")
                    try await Task.sleep(for: .milliseconds(300))
                    try require(service.current()?.id == other.id, "Changed input source without an app activation")
                    let started = ProcessInfo.processInfo.systemUptime
                    events.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
                    try await waitFor("Recovery exceeded 500 ms") { service.current()?.id == target.id }
                    let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1_000
                    print("PASS recovery \(target.name) #\(round): \(String(format: "%.1f", elapsed)) ms")
                    try await Task.sleep(for: .milliseconds(250))
                    try require(controller.restorationCount == countBeforeRecovery + 1, "A recovery was not counted exactly once")
                    try require(store.loadRestorationCount() == controller.restorationCount, "Restoration count was not persisted")
                }
                let countBeforeUnlock = controller.restorationCount
                controller.unlock()
                _ = service.select(other.id)
                try await Task.sleep(for: .milliseconds(300))
                try require(service.current()?.id == other.id, "Unlocked app still restored a source")
                try require(controller.restorationCount == countBeforeUnlock, "Unlocked switching changed statistics")
                print("PASS unlock \(target.name)")
            }

            _ = service.select(original.id)
            controller.lockCurrent()
            let countBeforeSecureInput = controller.restorationCount
            try require(EnableSecureEventInput() == noErr, "Cannot enable test secure input")
            ownsSecureInput = true
            events.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            try await waitFor("Secure input did not pause", timeout: 0.6) { controller.status == .paused(.secureInput) }
            let alternate = sources.first { $0.id != original.id }!
            _ = service.select(alternate.id)
            let duringSecureInput = service.current()?.id
            try await Task.sleep(for: .milliseconds(300))
            try require(service.current()?.id == duringSecureInput, "Changed source during secure input")
            try require(controller.target == original, "Secure input replaced the lock target")
            try require(controller.restorationCount == countBeforeSecureInput, "Secure input pause changed statistics")
            DisableSecureEventInput()
            ownsSecureInput = false
            try await Task.sleep(for: .milliseconds(500))
            try require(service.current()?.id == duringSecureInput, "Resumed secure input without an app activation")
            events.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            try await waitFor("Did not resume on the next activation") {
                controller.status == .locked && service.current()?.id == original.id
            }
            print("PASS real secure-input pause / resume on next app activation")

            let countBeforeRestart = controller.restorationCount
            controller.stop()
            _ = service.select(alternate.id)
            try await Task.sleep(for: .milliseconds(250))
            try require(service.current()?.id == alternate.id, "Stopped controller still selected a source")
            controller = LockController(store: store, workspaceNotifications: events)
            try await waitFor("Restart did not restore the saved lock") {
                controller.isEnabled && service.current()?.id == original.id
            }
            try require(controller.restorationCount == countBeforeRestart + 1, "Restart lost statistics or miscounted recovery")
            print("PASS persisted lock / controller restart / stop")
            print("PASS restoration statistics: exact increments, persistence, and pause / unlock exclusions")

            events.post(name: NSWorkspace.willSleepNotification, object: nil)
            try require(controller.status == .paused(.sessionInactive), "Sleep notification did not pause")
            _ = service.select(alternate.id)
            events.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await Task.sleep(for: .milliseconds(300))
            try require(service.current()?.id == alternate.id, "Wake unexpectedly restored without activation")
            events.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            try await waitFor("Activation after wake did not restore") { service.current()?.id == original.id }
            print("PASS simulated wake waits for app activation")

            if CommandLine.arguments.contains("--activate-apps") {
                controller.stop()
                controller = LockController(store: store)
                for bundleID in ["com.apple.Safari", "com.apple.TextEdit", "com.apple.Terminal", "com.apple.Safari"] {
                    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID else { continue }
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                        throw ProbeError.failed("Application unavailable: \(bundleID)")
                    }
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    try require(!service.isSecureInputEnabled, "Secure input prevents the foreground test")
                    _ = service.select(alternate.id)
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    try await waitFor("Could not restore in \(bundleID)") { service.current()?.id == original.id }
                    try await Task.sleep(for: .milliseconds(250))
                    try require(service.current()?.id == original.id, "Input source changed again after activation")
                    print("PASS foreground application \(bundleID)")
                }
                controller.stop()
                controller = LockController(store: store, workspaceNotifications: events)
            }

            // Reset the contention window, then force enough switches to trip it.
            controller.retry()
            for _ in 0..<6 {
                _ = service.select(alternate.id)
                events.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
                try await Task.sleep(for: .milliseconds(300))
            }
            try require(controller.status == .paused(.fault(.frequentChanges)), "Contention did not pause")
            controller.retry()
            try await waitFor("Manual retry did not restore") { service.current()?.id == original.id }
            print("PASS real contention limit / manual retry")
            controller.unlock()
            print("PASS integration completed; original input source will be restored.")
            return true
        } catch {
            print("FAIL: \(error)")
            return false
        }
    }

    /// Exercise the automatic trigger boundary using isolated app notifications.
    /// Staying in one app must cause no periodic queries, including during pauses.
    static func verifyActivationPolicy() async throws {
        let service = SimulatedInputSourceService()
        let suite = "app.imelock.IntegrationProbe.Power.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw ProbeError.failed("Cannot create power-test preferences")
        }
        let workspace = NotificationCenter()
        let controller = LockController(store: ConfigurationStore(defaults: defaults), service: service, workspaceNotifications: workspace)
        defer {
            controller.stop()
            defaults.removePersistentDomain(forName: suite)
        }
        try require(controller.activationDelayMilliseconds == 200, "Missing delay must default to 200 ms")
        controller.lockCurrent()
        controller.setActivationDelayMilliseconds(600)
        service.source = service.alternate
        service.resetQueries()
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try await Task.sleep(for: .milliseconds(300))
        try require(service.selections == 0, "Custom delay restored too early")
        try await waitFor("Custom delay did not restore") { service.source == service.target }
        let reopened = LockController(store: ConfigurationStore(defaults: defaults), service: service, workspaceNotifications: NotificationCenter())
        try require(reopened.activationDelayMilliseconds == 600, "Delay was not retained after reopening")
        reopened.stop()
        try await Task.sleep(for: .milliseconds(200))
        service.source = service.alternate
        service.resetQueries()
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        controller.setActivationDelayMilliseconds(50)
        try await waitFor("Pending activation did not adopt shorter delay", timeout: 0.3) { service.source == service.target }
        try require(service.selections == 1, "Changing delay duplicated the selection")
        controller.setActivationDelayMilliseconds(200)
        controller.unlock()
        let countBefore = controller.restorationCount
        print("PASS configurable delay, persistence, and rescheduling pending activation")
        service.resetQueries()
        try await Task.sleep(for: .milliseconds(1_250))
        try require(service.totalQueries == 0, "Unlocked controller performed periodic queries")

        controller.lockCurrent()
        service.resetQueries()
        try await Task.sleep(for: .milliseconds(1_300))
        try require(service.totalQueries == 0, "Stable lock performed periodic queries")
        service.source = service.alternate
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(600))
        try require(service.totalQueries == 0, "Same-app source or Space change triggered a check")
        controller.refresh()
        try require(controller.currentSource == service.alternate && service.selections == 0,
                    "Opening the menu unexpectedly restored the source")
        service.resetQueries()
        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<3 {
            workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await waitFor("App activation did not restore") { service.source == service.target }
        try require(service.selections == 1 && controller.restorationCount == countBefore + 1, "Rapid activations were not coalesced")
        print("PASS zero idle queries, no same-app/Space restoration, coalesced activation: \(String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - started) * 1_000)) ms")

        service.source = service.alternate
        service.ignoreSelection = true
        service.resetQueries()
        for attempt in 1...3 {
            workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            try await Task.sleep(for: .milliseconds(500))
            try require(service.selections == attempt, "An activation made more than one selection")
        }
        try require(controller.status == .paused(.fault(.restorationFailed)), "Three failed activation checks did not pause")
        service.resetQueries()
        try await Task.sleep(for: .milliseconds(600))
        try require(service.totalQueries == 0, "Fault pause continued polling")
        service.ignoreSelection = false
        controller.retry()
        try require(service.source == service.target && controller.status == .locked, "Manual retry did not restart monitoring")

        service.secureInput = true
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try await waitFor("Secure-input activation did not pause") { controller.status == .paused(.secureInput) }
        service.resetQueries()
        try await Task.sleep(for: .milliseconds(1_250))
        try require(service.totalQueries == 0, "Secure-input pause performed periodic queries")
        service.source = service.alternate
        service.secureInput = false
        try await Task.sleep(for: .milliseconds(400))
        try require(service.totalQueries == 0 && service.source == service.alternate, "Safe input ending restored without an activation")
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try await waitFor("Next activation did not resume") {
            controller.status == .locked && service.source == service.target
        }
        print("PASS one bounded confirmation per activation; fault / secure-input pauses have zero polling")

        for (suspend, resume) in [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification)
        ] {
            workspace.post(name: suspend, object: nil)
            try require(controller.status == .paused(.sessionInactive), "Inactive session did not pause")
            service.resetQueries()
            try await Task.sleep(for: .milliseconds(600))
            try require(service.totalQueries == 0, "Inactive session continued polling")
            service.source = service.alternate
            workspace.post(name: resume, object: nil)
            try await Task.sleep(for: .milliseconds(250))
            try require(service.totalQueries == 0 && service.source == service.alternate, "Wake checked before an activation")
            workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
            try await waitFor("Activation after wake did not recover") { service.source == service.target }
        }
        service.source = service.alternate
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        controller.unlock()
        service.resetQueries()
        try await Task.sleep(for: .milliseconds(600))
        try require(service.totalQueries == 0, "Unlock did not cancel the pending activation")
        controller.lockCurrent()
        service.source = service.target
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        controller.stop()
        service.resetQueries()
        try await Task.sleep(for: .milliseconds(300))
        try require(service.totalQueries == 0, "Stop did not cancel the pending activation")
        print("PASS wake waits for activation; unlock / stop cancel queued checks")
    }
}
