import Foundation
import Testing
@testable import IMELockCore

private let abc = InputSource(id: "abc", name: "ABC")
private let pinyin = InputSource(id: "pinyin", name: "拼音")

private func snapshot(
    current: InputSource? = abc,
    secure: Bool = false,
    active: Bool = true,
    available: Set<String> = ["abc", "pinyin"]
) -> InputSnapshot {
    InputSnapshot(current: current, availableIDs: available, isSecureInput: secure, isSessionActive: active)
}

@Test func unlockedNeverSelects() {
    var engine = LockEngine()
    #expect(engine.reconcile(snapshot(), now: 0) == nil)
    #expect(engine.status == .unlocked)
}

@Test func restoresExplicitTargetWithoutAdoptingNewSource() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    #expect(engine.reconcile(snapshot(), now: 0) == pinyin)
    engine.recordSelectionResult(.selected)
    #expect(engine.reconcile(snapshot(current: pinyin), now: 0.01) == nil)
    #expect(engine.status == .locked)
    #expect(engine.configuration.target == pinyin)
    #expect(engine.reconcile(snapshot(), now: 0.3) == pinyin)
    engine.unlock()
    #expect(engine.reconcile(snapshot(), now: 0.6) == nil)
    #expect(engine.status == .unlocked)
}

@Test func secureInputNeverSelectsAndResumesOriginalTarget() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    #expect(engine.reconcile(snapshot(secure: true), now: 0) == nil)
    #expect(engine.status == .paused(.secureInput))
    #expect(engine.reconcile(snapshot(secure: true, available: []), now: 10) == nil)
    #expect(engine.configuration.fault == nil)
    #expect(engine.reconcile(snapshot(), now: 11) == pinyin)
}

@Test func sessionSuspensionResetsInterruptedRetries() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(), now: 0)
    engine.recordSelectionResult(.failed(-50))
    _ = engine.reconcile(snapshot(), now: 0.2)
    engine.recordSelectionResult(.failed(-50))
    #expect(engine.reconcile(snapshot(active: false, available: []), now: 1) == nil)
    #expect(engine.status == .paused(.sessionInactive))
    #expect(engine.reconcile(snapshot(), now: 100) == pinyin)
    engine.recordSelectionResult(.failed(-50))
    #expect(engine.configuration.fault == nil)
}

@Test func missingTargetLatchesUntilManualRetry() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    #expect(engine.reconcile(snapshot(available: ["abc"]), now: 0) == nil)
    #expect(engine.status == .paused(.fault(.targetUnavailable)))
    #expect(engine.reconcile(snapshot(), now: 1) == nil)
    #expect(engine.reconcile(snapshot(secure: true), now: 2) == nil)
    #expect(engine.configuration.fault == .targetUnavailable)
    engine.retry()
    #expect(engine.reconcile(snapshot(), now: 3) == pinyin)
}

@Test func duplicateNotificationsDoNotConsumeRetryBudget() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    #expect(engine.reconcile(snapshot(), now: 0) == pinyin)
    engine.recordSelectionResult(.selected)
    for tick in 1...100 {
        #expect(engine.reconcile(snapshot(), now: Double(tick) / 1_000) == nil)
    }
    #expect(engine.configuration.fault == nil)
    #expect(engine.reconcile(snapshot(current: pinyin), now: 0.11) == nil)
    #expect(engine.status == .locked)
}

@Test func successfulAPIReturnWithoutActualSwitchStopsAfterThreeAttempts() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    for now in [0.0, 0.2, 0.4] {
        #expect(engine.reconcile(snapshot(), now: now) == pinyin)
        engine.recordSelectionResult(.selected)
    }
    #expect(engine.reconcile(snapshot(), now: 0.6) == nil)
    #expect(engine.status == .paused(.fault(.restorationFailed)))
    #expect(engine.reconcile(snapshot(), now: 100) == nil)
    #expect(engine.restorationCount == 0)
}

@Test func selectionErrorsAreBoundedAndCanBeRetried() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    for now in [0.0, 0.2, 0.4] {
        #expect(engine.reconcile(snapshot(), now: now) == pinyin)
        engine.recordSelectionResult(.failed(-50))
    }
    #expect(engine.status == .paused(.fault(.restorationFailed)))
    #expect(engine.lastErrorCode == -50)
    engine.retry()
    #expect(engine.reconcile(snapshot(), now: 1) == pinyin)
    engine.recordSelectionResult(.selected)
    #expect(engine.reconcile(snapshot(current: pinyin), now: 1.01) == nil)
    #expect(engine.lastErrorCode == nil)
}

@Test func targetRemovedBetweenObservationAndSelectionPauses() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(), now: 0)
    engine.recordSelectionResult(.unavailable)
    #expect(engine.status == .paused(.fault(.targetUnavailable)))
}

@Test func successfulButRepeatedContentionAlsoStops() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    for step in 0..<5 {
        let now = Double(step) * 0.2
        #expect(engine.reconcile(snapshot(), now: now) == pinyin)
        engine.recordSelectionResult(.selected)
        #expect(engine.reconcile(snapshot(current: pinyin), now: now + 0.01) == nil)
    }
    #expect(engine.reconcile(snapshot(), now: 1.1) == nil)
    #expect(engine.status == .paused(.fault(.frequentChanges)))
    #expect(engine.restorationCount == 5)
}

@Test func occasionalSwitchesDoNotAccumulateIntoContention() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    for step in 0..<20 {
        let now = Double(step) * 3
        #expect(engine.reconcile(snapshot(), now: now) == pinyin)
        engine.recordSelectionResult(.selected)
        #expect(engine.reconcile(snapshot(current: pinyin), now: now + 0.01) == nil)
    }
    #expect(engine.configuration.fault == nil)
}

@Test func secureInputInterruptsPendingSelectionWithoutProducingFault() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(), now: 0)
    engine.recordSelectionResult(.selected)
    #expect(engine.reconcile(snapshot(secure: true), now: 0.1) == nil)
    #expect(engine.reconcile(snapshot(), now: 10) == pinyin)
    #expect(engine.configuration.fault == nil)
}

@Test func unavailableCurrentSourceCannotBeMistakenForSuccess() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    for now in [0.0, 0.2, 0.4] {
        #expect(engine.reconcile(snapshot(current: nil), now: now) == pinyin)
        engine.recordSelectionResult(.selected)
    }
    #expect(engine.reconcile(snapshot(current: nil), now: 0.6) == nil)
    #expect(engine.configuration.fault == .restorationFailed)
}

@Test func restoringConfigurationPreservesTargetAndFault() throws {
    let suite = "IMELockTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ConfigurationStore(defaults: defaults)
    #expect(store.load() == LockConfiguration())

    let saved = LockConfiguration(target: pinyin, isEnabled: true, fault: .frequentChanges)
    store.save(saved)
    var engine = LockEngine(configuration: store.load())
    #expect(engine.reconcile(snapshot(), now: 0) == nil)
    #expect(engine.status == .paused(.fault(.frequentChanges)))
    #expect(engine.configuration.target == pinyin)

    engine.retry()
    store.save(engine.configuration)
    var restarted = LockEngine(configuration: store.load())
    #expect(restarted.reconcile(snapshot(), now: 0) == pinyin)
    restarted.unlock()
    store.save(restarted.configuration)
    #expect(!store.load().isEnabled)
}

@Test func invalidSavedConfigurationStartsUnlocked() throws {
    let suite = "IMELockTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ConfigurationStore(defaults: defaults)
    defaults.set(Data("broken".utf8), forKey: "inputSourceLock.v1")
    #expect(store.load() == LockConfiguration())
    store.save(LockConfiguration(isEnabled: true))
    #expect(store.load() == LockConfiguration())
}

@Test func countsConfirmedRestorationsOnceAndKeepsTotalAcrossTargets() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(current: pinyin), now: 0)
    #expect(engine.restorationCount == 0)

    #expect(engine.reconcile(snapshot(), now: 1) == pinyin)
    engine.recordSelectionResult(.selected)
    #expect(engine.restorationCount == 0)
    _ = engine.reconcile(snapshot(current: pinyin), now: 1.01)
    #expect(engine.restorationCount == 1)
    for tick in 1...100 {
        _ = engine.reconcile(snapshot(current: pinyin), now: 1.01 + Double(tick) / 100)
    }
    #expect(engine.restorationCount == 1)

    engine.unlock()
    _ = engine.reconcile(snapshot(), now: 3)
    engine.lock(to: abc)
    _ = engine.reconcile(snapshot(), now: 4)
    #expect(engine.restorationCount == 1)
    _ = engine.reconcile(snapshot(current: pinyin), now: 5)
    engine.recordSelectionResult(.selected)
    _ = engine.reconcile(snapshot(), now: 5.01)
    #expect(engine.restorationCount == 2)
}

@Test func countsSuccessfulRecoveryAfterRetriesOnlyOnce() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(), now: 0)
    engine.recordSelectionResult(.failed(-50))
    _ = engine.reconcile(snapshot(), now: 0.2)
    engine.recordSelectionResult(.selected)
    _ = engine.reconcile(snapshot(), now: 0.4)
    engine.recordSelectionResult(.selected)
    #expect(engine.restorationCount == 0)
    _ = engine.reconcile(snapshot(current: pinyin), now: 0.41)
    _ = engine.reconcile(snapshot(current: pinyin), now: 1)
    #expect(engine.restorationCount == 1)
}

@Test func failedOrUnperformedSelectionDoesNotCountAnExternalReturn() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(), now: 0)
    // No accepted selection: another process returned to the target.
    _ = engine.reconcile(snapshot(current: pinyin), now: 0.01)
    #expect(engine.restorationCount == 0)

    _ = engine.reconcile(snapshot(), now: 1)
    engine.recordSelectionResult(.failed(-50))
    _ = engine.reconcile(snapshot(current: pinyin), now: 1.01)
    #expect(engine.restorationCount == 0)
}

@Test func interruptedRecoveryIsNotCountedAfterPauseOrUnlock() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(), now: 0)
    engine.recordSelectionResult(.selected)
    _ = engine.reconcile(snapshot(secure: true), now: 0.01)
    _ = engine.reconcile(snapshot(current: pinyin), now: 1)
    #expect(engine.restorationCount == 0)

    _ = engine.reconcile(snapshot(), now: 2)
    engine.recordSelectionResult(.selected)
    engine.unlock()
    _ = engine.reconcile(snapshot(current: pinyin), now: 2.01)
    #expect(engine.restorationCount == 0)
}

@Test func unreadableSourceIsNotCountedAsAnObservedSwitch() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(current: nil), now: 0)
    engine.recordSelectionResult(.selected)
    _ = engine.reconcile(snapshot(current: pinyin), now: 0.01)
    #expect(engine.restorationCount == 0)
}

@Test func statisticsPersistWithoutChangingExistingLockConfiguration() throws {
    let suite = "IMELockTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ConfigurationStore(defaults: defaults)
    let configuration = LockConfiguration(target: pinyin, isEnabled: true)
    store.save(configuration)
    // Existing installations have a lock configuration but no statistics key.
    #expect(store.loadRestorationCount() == 0)
    store.saveRestorationCount(12)
    let reopenedStore = ConfigurationStore(defaults: try #require(UserDefaults(suiteName: suite)))
    var restarted = LockEngine(configuration: reopenedStore.load(), restorationCount: reopenedStore.loadRestorationCount())
    _ = restarted.reconcile(snapshot(current: pinyin), now: 0)
    #expect(restarted.restorationCount == 12)
    _ = restarted.reconcile(snapshot(), now: 1)
    restarted.recordSelectionResult(.selected)
    _ = restarted.reconcile(snapshot(current: pinyin), now: 1.01)
    store.saveRestorationCount(restarted.restorationCount)
    #expect(reopenedStore.loadRestorationCount() == 13)
    #expect(store.load() == configuration)
}

@Test func confirmationDoesNotRetryAndCountsEachFailedAttemptOnce() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    for attempt in 0..<3 {
        let now = Double(attempt)
        #expect(engine.reconcile(snapshot(), now: now) == pinyin)
        engine.recordSelectionResult(.selected)
        #expect(engine.reconcile(snapshot(), now: now + 0.2, allowsSelection: false) == nil)
        #expect(engine.reconcile(snapshot(), now: now + 0.3, allowsSelection: false) == nil)
        if attempt < 2 { #expect(engine.configuration.fault == nil) }
    }
    #expect(engine.configuration.fault == .restorationFailed)
    #expect(engine.restorationCount == 0)
}

@Test func boundedConfirmationCountsDelayedSuccessOnce() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    #expect(engine.reconcile(snapshot(), now: 0) == pinyin)
    engine.recordSelectionResult(.selected)
    #expect(engine.reconcile(snapshot(current: pinyin), now: 0.2, allowsSelection: false) == nil)
    #expect(engine.restorationCount == 1)
    #expect(engine.reconcile(snapshot(), now: 1, allowsSelection: false) == nil)
    #expect(engine.restorationCount == 1)
    #expect(engine.configuration.fault == nil)
}

@Test func sessionTransitionsCancelPendingConfirmationAndPreserveFaults() {
    var engine = LockEngine()
    engine.lock(to: pinyin)
    _ = engine.reconcile(snapshot(), now: 0)
    engine.recordSelectionResult(.selected)
    engine.setSessionActive(false)
    #expect(engine.status == .paused(.sessionInactive))
    engine.setSessionActive(true)
    #expect(engine.status == .locked)
    _ = engine.reconcile(snapshot(current: pinyin), now: 1, allowsSelection: false)
    #expect(engine.restorationCount == 0)

    _ = engine.reconcile(snapshot(available: ["abc"]), now: 2)
    engine.setSessionActive(false)
    engine.setSessionActive(true)
    #expect(engine.status == .paused(.fault(.targetUnavailable)))
    #expect(engine.configuration.fault == .targetUnavailable)
}
