import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemManager {
    private(set) var status = SMAppService.mainApp.status
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer {
            refresh()
            isUpdating = false
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
