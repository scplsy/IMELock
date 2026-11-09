import Carbon
import Foundation

@MainActor
protocol InputSourceProviding {
    func current() -> InputSource?
    func available() -> [InputSource]
    var isSecureInputEnabled: Bool { get }
    func select(_ id: String) -> SelectionResult
}

/// All TIS and secure-input calls run on the main thread, as required by HIToolbox.
@MainActor
final class InputSourceService: InputSourceProviding {
    func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return describe(source)
    }

    func available() -> [InputSource] {
        selectableSources().compactMap(describe)
    }

    var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    func select(_ id: String) -> SelectionResult {
        guard let source = selectableSources().first(where: {
            stringProperty($0, kTISPropertyInputSourceID) == id
        }) else {
            return .unavailable
        }
        let result = TISSelectInputSource(source)
        return result == noErr ? .selected : .failed(result)
    }

    private func selectableSources() -> [TISInputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceIsEnabled as String: true
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return []
        }
        return (list as NSArray) as? [TISInputSource] ?? []
    }

    private func describe(_ source: TISInputSource) -> InputSource? {
        guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
        return InputSource(id: id, name: stringProperty(source, kTISPropertyLocalizedName) ?? id)
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
