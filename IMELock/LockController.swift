import AppKit
import Observation

@MainActor
@Observable
final class LockController: NSObject {
    private(set) var status: LockStatus = .unlocked
    private(set) var currentSource: InputSource?
    private(set) var target: InputSource?
    private(set) var isEnabled = false
    private(set) var lastErrorCode: Int32?
    private(set) var restorationCount: Int
    private(set) var activationDelayMilliseconds: Int

    @ObservationIgnored private let service: any InputSourceProviding
    @ObservationIgnored private let store: ConfigurationStore
    @ObservationIgnored private let workspaceNotifications: NotificationCenter
    @ObservationIgnored private var engine: LockEngine
    @ObservationIgnored private var persistedConfiguration: LockConfiguration
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?
    @ObservationIgnored private var availableIDs = Set<String>()
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var displaySleeping = false
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private var reconciling = false
    @ObservationIgnored private var stopped = false

    init(
        store: ConfigurationStore = ConfigurationStore(),
        service: any InputSourceProviding = InputSourceService(),
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.service = service
        self.store = store
        self.workspaceNotifications = workspaceNotifications
        let configuration = store.load()
        let restorationCount = store.loadRestorationCount()
        self.restorationCount = restorationCount
        activationDelayMilliseconds = store.loadActivationDelayMilliseconds()
        engine = LockEngine(configuration: configuration, restorationCount: restorationCount)
        persistedConfiguration = configuration
        super.init()
        refreshSessionActivity()
        observeSystem()
        checkOnce()
    }

    func lockCurrent() {
        // Query at the moment of the click, rather than locking a stale menu value.
        guard let current = service.current() else { return }
        cancelPendingChecks()
        engine.lock(to: current)
        checkOnce()
    }

    func unlock() {
        cancelPendingChecks()
        engine.unlock()
        publish()
    }

    func retry() {
        cancelPendingChecks()
        engine.retry()
        checkOnce()
    }

    func setActivationDelayMilliseconds(_ value: Int) {
        store.saveActivationDelayMilliseconds(value)
        activationDelayMilliseconds = store.loadActivationDelayMilliseconds()
        // An already queued activation uses the new delay from this moment.
        if activationTask != nil { scheduleActivationCheck() }
    }

    func refresh() {
        // Opening the menu/settings only refreshes the displayed source; it must
        // not restore a source changed while the user stays in the same app.
        guard !stopped, isSessionActive else { return }
        currentSource = service.current()
    }

    func stop() {
        stopped = true
        cancelPendingChecks()
        workspaceNotifications.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func observeSystem() {
        let workspace = workspaceNotifications
        workspace.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displayDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displayDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate), name: NSApplication.willTerminateNotification, object: nil)
    }

    @objc private func applicationChanged(_ notification: Notification) {
        scheduleActivationCheck()
    }

    private func scheduleActivationCheck() {
        cancelPendingChecks()
        guard !stopped, isSessionActive, engine.configuration.isEnabled,
              engine.configuration.fault == nil else { return }
        // App activation can precede macOS restoring that app's input source.
        // Coalesce rapid switches into one check after the last activation.
        let delay = activationDelayMilliseconds
        activationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.activationTask = nil
            self.checkOnce()
        }
    }

    @objc private func willTerminate(_ notification: Notification) { stop() }

    @objc private func willSleep(_ notification: Notification) {
        sleeping = true
        updateSessionState()
    }

    @objc private func didWake(_ notification: Notification) {
        sleeping = false
        refreshSessionActivity()
        updateSessionState()
    }

    @objc private func displayDidSleep(_ notification: Notification) {
        displaySleeping = true
        updateSessionState()
    }

    @objc private func displayDidWake(_ notification: Notification) {
        displaySleeping = false
        refreshSessionActivity()
        updateSessionState()
    }

    @objc private func sessionResigned(_ notification: Notification) {
        sessionActive = false
        updateSessionState()
    }

    @objc private func sessionActivated(_ notification: Notification) {
        sessionActive = true
        updateSessionState()
    }

    private func refreshSessionActivity() {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            sessionActive = session[kCGSessionOnConsoleKey as String] as? Bool ?? true
        }
    }

    private var isSessionActive: Bool {
        sessionActive && !sleeping && !displaySleeping
    }

    private func cancelPendingChecks() {
        activationTask?.cancel()
        activationTask = nil
        confirmationTask?.cancel()
        confirmationTask = nil
    }

    private func updateSessionState() {
        cancelPendingChecks()
        engine.setSessionActive(isSessionActive)
        publish()
    }

    private func checkOnce() {
        guard !stopped, !reconciling else { return }
        reconciling = true
        defer { reconciling = false }

        let now = ProcessInfo.processInfo.systemUptime
        guard isSessionActive else {
            engine.setSessionActive(false)
            publish()
            return
        }

        let canRestore = engine.configuration.isEnabled && engine.configuration.fault == nil
        // Refresh only for an activation/manual check, never on a timer.
        if canRestore {
            availableIDs = Set(service.available().map(\.id))
        }
        var snapshot = InputSnapshot(
            current: service.current(), availableIDs: availableIDs,
            isSecureInput: canRestore && service.isSecureInputEnabled,
            isSessionActive: true
        )
        if let target = engine.reconcile(snapshot, now: now) {
            // Check again immediately before selection: secure input may have
            // started while the current source and availability were queried.
            snapshot.isSecureInput = service.isSecureInputEnabled
            if snapshot.isSecureInput {
                _ = engine.reconcile(snapshot, now: now)
            } else {
                let result = service.select(target.id)
                engine.recordSelectionResult(result)
                snapshot.current = service.current()
                snapshot.isSecureInput = service.isSecureInputEnabled
                if snapshot.current?.id == target.id || snapshot.isSecureInput {
                    _ = engine.reconcile(snapshot, now: ProcessInfo.processInfo.systemUptime, allowsSelection: false)
                } else if result == .selected {
                    scheduleConfirmation()
                }
            }
        }
        currentSource = snapshot.current
        publish()
    }

    private func scheduleConfirmation() {
        guard engine.configuration.fault == nil else { return }
        // One bounded confirmation belongs to this activation. It never selects
        // again or schedules another check, even if the source failed to change.
        confirmationTask?.cancel()
        confirmationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard !Task.isCancelled, let self, !self.stopped, self.isSessionActive else { return }
            self.confirmationTask = nil
            let snapshot = InputSnapshot(
                current: self.service.current(), availableIDs: self.availableIDs,
                isSecureInput: self.service.isSecureInputEnabled
            )
            _ = self.engine.reconcile(snapshot, now: ProcessInfo.processInfo.systemUptime, allowsSelection: false)
            self.currentSource = snapshot.current
            self.publish()
        }
    }

    private func publish() {
        status = engine.status
        target = engine.configuration.target
        isEnabled = engine.configuration.isEnabled
        lastErrorCode = engine.lastErrorCode
        if persistedConfiguration != engine.configuration {
            store.save(engine.configuration)
            persistedConfiguration = engine.configuration
        }
        if restorationCount != engine.restorationCount {
            restorationCount = engine.restorationCount
            store.saveRestorationCount(restorationCount)
        }
    }
}
