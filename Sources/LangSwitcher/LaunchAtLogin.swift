import CoreServices
import Foundation

enum LaunchAtLogin {
    static var isEnabled: Bool {
        guard let loginItems = LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue() else {
            return false
        }
        let appURL = Bundle.main.bundleURL as CFURL
        let snapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem]
            ?? []
        for item in snapshot {
            guard let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() else {
                continue
            }
            if CFEqual(url, appURL) {
                return true
            }
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard let loginItems = LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue() else {
            throw LaunchAtLoginError.loginItemsUnavailable
        }
        let appURL = Bundle.main.bundleURL as CFURL
        if enabled {
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
            return
        }
        let snapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem]
            ?? []
        for item in snapshot {
            guard let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() else {
                continue
            }
            if CFEqual(url, appURL) {
                LSSharedFileListItemRemove(loginItems, item)
                return
            }
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
