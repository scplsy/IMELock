import Foundation

struct ConfigurationStore {
    static let defaultActivationDelayMilliseconds = 200
    static let activationDelayRange = 50...1000

    private let defaults: UserDefaults
    private let key = "inputSourceLock.v1"
    private let activationDelayKey = "inputSourceLock.activationDelayMilliseconds.v1"
    private let restorationCountKey = "inputSourceLock.restorationCount.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LockConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(LockConfiguration.self, from: data),
              !configuration.isEnabled || configuration.target?.id.isEmpty == false else {
            return LockConfiguration()
        }
        return configuration
    }

    func save(_ configuration: LockConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }

    func loadActivationDelayMilliseconds() -> Int {
        guard defaults.object(forKey: activationDelayKey) != nil else {
            return Self.defaultActivationDelayMilliseconds
        }
        let value = defaults.integer(forKey: activationDelayKey)
        return Self.activationDelayRange.contains(value) ? value : Self.defaultActivationDelayMilliseconds
    }

    func saveActivationDelayMilliseconds(_ value: Int) {
        defaults.set(min(max(value, Self.activationDelayRange.lowerBound), Self.activationDelayRange.upperBound),
                     forKey: activationDelayKey)
    }

    func loadRestorationCount() -> Int {
        max(0, defaults.integer(forKey: restorationCountKey))
    }

    func saveRestorationCount(_ count: Int) {
        defaults.set(max(0, count), forKey: restorationCountKey)
    }
}
