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
        removeAllItems(for: bundleID, in: loginItems)
        guard enabled else {
            return
        }
        let appURL = Bundle.main.bundleURL as CFURL
        let added = LSSharedFileListInsertItemURL(
            loginItems,
            kLSSharedFileListItemLast.takeUnretainedValue(),
            nil,
            nil,
            appURL,
            nil,
            nil
        )
        if added == nil {
            throw LaunchAtLoginError.addFailed
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

    private static func itemMatchesApp(item: LSSharedFileListItem, bundleID: String) -> Bool {
        guard let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL? else {
            return false
        }
        if url == Bundle.main.bundleURL {
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
