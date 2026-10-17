import AppKit
import Foundation

enum PermissionOnboarding {
    /// Requests system prompts and guides the user when TCC is not granted yet.
    static func runIfNeeded(onGranted: @escaping () -> Void) {
        if PermissionPrompts.hasAccessibility && PermissionPrompts.hasInputMonitoring {
            onGranted()
            return
        }

        requestSystemPrompts()

        let alert = NSAlert()
        alert.messageText = "Lang Switcher needs two permissions"
        alert.informativeText = """
        macOS keeps these separate from each other.

        1. When asked to “control this Mac”, click Open System Settings — not Deny.
        2. In Device Control and Data Access → turn LangSwitcher ON.
        3. In Input Monitoring → turn LangSwitcher ON (add /Applications/LangSwitcher.app with + if needed).
        4. Click OK here, then Quit Lang Switcher (menu → Quit) and open it again from Applications.

        App: \(PermissionPrompts.appLocationForPermissions())
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Device Control settings")
        alert.addButton(withTitle: "Open Input Monitoring")
        alert.addButton(withTitle: "OK")

        schedulePermissionPoll(onGranted: onGranted)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            PermissionPrompts.openAccessibilitySettings()
        case .alertSecondButtonReturn:
            PermissionPrompts.openInputMonitoringSettings()
        default:
            break
        }
    }

    private static func requestSystemPrompts() {
        _ = PermissionPrompts.requestInputMonitoringIfNeeded()
        PermissionPrompts.requestAccessibilityPromptIfNeeded()
    }

    private static func schedulePermissionPoll(onGranted: @escaping () -> Void) {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard PermissionPrompts.hasAccessibility && PermissionPrompts.hasInputMonitoring else {
                return
            }
            timer.invalidate()
            onGranted()
        }
    }
}
