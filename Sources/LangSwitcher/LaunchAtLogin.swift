import CoreServices
import Foundation

enum LaunchAtLogin {
    static var isEnabled: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return false
        }
        guard let loginItems = sessionLoginItems() else {
            return false
        }
        return snapshot(loginItems).contains { itemMatchesApp(item: $0, bundleID: bundleID) }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw LaunchAtLoginError.loginItemsUnavailable
        }
        guard let loginItems = sessionLoginItems() else {
            throw LaunchAtLoginError.loginItemsUnavailable
        }
        guard enabled else {
            removeAllItems(for: bundleID, in: loginItems)
            return
        }

        let appURL = Bundle.main.bundleURL
        let existing = snapshot(loginItems).filter { itemMatchesApp(item: $0, bundleID: bundleID) }
        let onlyCurrent = existing.count == 1 && itemResolvesToCurrentApp(existing[0])
        if onlyCurrent {
            return
        }

        let before = snapshot(loginItems)
        let added = LSSharedFileListInsertItemURL(
            loginItems,
            kLSSharedFileListItemLast.takeUnretainedValue(),
            nil,
            nil,
            appURL as CFURL,
            nil,
            nil
        )
        if added == nil {
            throw LaunchAtLoginError.addFailed
        }
        for item in before where itemMatchesApp(item: item, bundleID: bundleID) {
            LSSharedFileListItemRemove(loginItems, item)
        }
    }

    private static func sessionLoginItems() -> LSSharedFileList? {
        LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue()
    }

    private static func snapshot(_ loginItems: LSSharedFileList) -> [LSSharedFileListItem] {
        LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] ?? []
    }

    private static func resolvedURL(for item: LSSharedFileListItem) -> URL? {
        LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?
    }

    private static func urlsReferToSameApp(_ url: URL, as current: URL) -> Bool {
        if url == current {
            return true
        }
        if url.resolvingSymlinksInPath().path == current.resolvingSymlinksInPath().path {
            return true
        }
        guard let expected = Bundle.main.bundleIdentifier else {
            return false
        }
        return Bundle(url: url)?.bundleIdentifier == expected
    }

    private static func itemResolvesToCurrentApp(_ item: LSSharedFileListItem) -> Bool {
        guard let url = resolvedURL(for: item) else {
            return false
        }
        return urlsReferToSameApp(url, as: Bundle.main.bundleURL)
    }

    private static func itemMatchesApp(item: LSSharedFileListItem, bundleID: String) -> Bool {
        guard let url = resolvedURL(for: item) else {
            return false
        }
        if urlsReferToSameApp(url, as: Bundle.main.bundleURL) {
            return true
        }
        return Bundle(url: url)?.bundleIdentifier == bundleID
    }

    private static func removeAllItems(for bundleID: String, in loginItems: LSSharedFileList) {
        for item in snapshot(loginItems) where itemMatchesApp(item: item, bundleID: bundleID) {
            LSSharedFileListItemRemove(loginItems, item)
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case loginItemsUnavailable
    case addFailed

    var errorDescription: String? {
        switch self {
        case .loginItemsUnavailable:
            return "Could not access login items."
        case .addFailed:
            return "Could not add Lang Switcher to login items."
        }
    }
}
