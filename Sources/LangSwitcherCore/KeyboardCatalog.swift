import Carbon
import Foundation

public struct InstalledLayout {
    public let id: String
    public let name: String
    public let language: Language
    public let enabled: Bool
    public let layoutData: Data
}

/// Finds the English, Swedish, and Russian keyboard layouts installed on this Mac.
public final class KeyboardCatalog {
    private final class Source {
        let id: String
        let name: String
        let primaryLanguage: String
        let layoutData: Data
        private let retained: Unmanaged<TISInputSource>

        init(
            id: String,
            name: String,
            primaryLanguage: String,
            layoutData: Data,
            retained: Unmanaged<TISInputSource>
        ) {
            self.id = id
            self.name = name
            self.primaryLanguage = primaryLanguage
            self.layoutData = layoutData
            self.retained = retained
        }

        deinit {
            retained.release()
        }

        var reference: TISInputSource {
            retained.takeUnretainedValue()
        }

        var isEnabled: Bool {
            guard let pointer = TISGetInputSourceProperty(reference, kTISPropertyInputSourceIsEnabled) else {
                return false
            }
            let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
            return CFBooleanGetValue(value)
        }
    }

    private var sources: [Source] = []

    public init() {
        refresh()
    }

    public func refresh() {
        sources.removeAll()
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() else {
            return
        }

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let value = CFArrayGetValueAtIndex(list, index) else {
                continue
            }
            let unmanaged = Unmanaged<TISInputSource>.fromOpaque(value).retain()
            let reference = unmanaged.takeUnretainedValue()
            guard
                let id = Self.string(kTISPropertyInputSourceID, from: reference),
                id.hasPrefix("com.apple.keylayout."),
                let name = Self.string(kTISPropertyLocalizedName, from: reference),
                let primary = Self.primaryLanguage(of: reference),
                let data = Self.layoutData(of: reference)
            else {
                unmanaged.release()
                continue
            }
            sources.append(
                Source(
                    id: id,
                    name: name,
                    primaryLanguage: primary,
                    layoutData: data,
                    retained: unmanaged
                )
            )
        }
    }

    public func layout(for language: Language) -> InstalledLayout? {
        if let current = currentSource(), current.primaryLanguage == language.rawValue {
            return installed(current)
        }

        let matches = sources.filter { $0.primaryLanguage == language.rawValue }
        let enabled = matches.filter { $0.isEnabled }
        let pool = enabled.isEmpty ? matches : enabled
        for identifier in language.preferredSourceIDs {
            if let source = pool.first(where: { $0.id == identifier }) {
                return installed(source)
            }
        }
        guard let source = pool.first else {
            return nil
        }
        return installed(source)
    }

    public func currentLanguage() -> Language? {
        guard let current = currentSource() else {
            return nil
        }
        return Language(rawValue: current.primaryLanguage)
    }

    public func currentLayoutName() -> String? {
        currentSource()?.name
    }

    /// Enables the layout if needed, then selects it.
    @discardableResult
    public func select(_ language: Language) -> Bool {
        guard let source = source(forSelecting: language) else {
            return false
        }
        if !source.isEnabled {
            let enableStatus = TISEnableInputSource(source.reference)
            if enableStatus != noErr {
                return false
            }
        }
        return TISSelectInputSource(source.reference) == noErr
    }

    private func source(forSelecting language: Language) -> Source? {
        if let current = currentSource(), current.primaryLanguage == language.rawValue {
            return current
        }
        let matches = sources.filter { $0.primaryLanguage == language.rawValue }
        let enabled = matches.filter { $0.isEnabled }
        let pool = enabled.isEmpty ? matches : enabled
        for identifier in language.preferredSourceIDs {
            if let source = pool.first(where: { $0.id == identifier }) {
                return source
            }
        }
        return pool.first
    }

    private func currentSource() -> Source? {
        guard let copy = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let id = Self.string(kTISPropertyInputSourceID, from: copy) else {
            return nil
        }
        return sources.first { $0.id == id }
    }

    private func installed(_ source: Source) -> InstalledLayout? {
        guard let language = Language(rawValue: source.primaryLanguage) else {
            return nil
        }
        return InstalledLayout(
            id: source.id,
            name: source.name,
            language: language,
            enabled: source.isEnabled,
            layoutData: source.layoutData
        )
    }

    private static func string(_ key: CFString, from source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func primaryLanguage(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue()
        guard CFArrayGetCount(array) > 0, let value = CFArrayGetValueAtIndex(array, 0) else {
            return nil
        }
        let code = Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
        return normalize(code)
    }

    private static func normalize(_ code: String) -> String {
        let lowered = code.lowercased()
        if let separator = lowered.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            return String(lowered[..<separator])
        }
        return lowered
    }

    private static func layoutData(of source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let length = CFDataGetLength(data)
        guard length > 0, let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        return Data(bytes: bytes, count: length)
    }
}
