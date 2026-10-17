import AppKit
import Foundation

import LangSwitcherCore

/// Only one Lang Switcher may run. A second copy (e.g. Desktop + Applications) breaks permissions.
enum SingleInstance {
    static func enforce() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let others = siblings.filter { $0.processIdentifier != currentPID }
        guard !others.isEmpty else {
            return
        }
        for app in others {
            app.terminate()
        }
        usleep(200_000)
    }
}

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let catalog = KeyboardCatalog()
    private var monitor: TypingMonitor?
    private var displayedLanguage: Language = .en
    private var isPaused = false
    private var retryTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        SingleInstance.enforce()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        displayedLanguage = catalog.currentLanguage() ?? .en
        statusItem.button?.title = displayedLanguage.title
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        let words = loadWords()
        let detector = LanguageDetector(words: words)
        let monitor = TypingMonitor(detector: detector, catalog: catalog)
        let savedPaused = UserDefaults.standard.object(forKey: "isPaused") as? Bool ?? false
        monitor.isPaused = savedPaused
        isPaused = savedPaused
        monitor.onLanguageChange = { [weak self] language in
            self?.displayedLanguage = language
            self?.refreshStatusTitle()
        }
        monitor.onPauseChange = { [weak self] paused in
            self?.isPaused = paused
            self?.refreshStatusTitle()
        }
        self.monitor = monitor
        refreshStatusTitle()

        PermissionOnboarding.runIfNeeded { [weak self] in
            self?.startKeyboardMonitor()
        }
    }

    private func startKeyboardMonitor() {
        guard let monitor = monitor else {
            return
        }
        if !monitor.start() {
            scheduleRetry()
        }
        refreshStatusTitle()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let listening = monitor?.isListening ?? false
        let accessibility = PermissionPrompts.hasAccessibility
        let inputMonitoring = PermissionPrompts.hasInputMonitoring

        let status = NSMenuItem(
            title: statusTitle(
                listening: listening,
                accessibility: accessibility,
                inputMonitoring: inputMonitoring,
                paused: isPaused
            ),
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        let accessLine = NSMenuItem(
            title: "Accessibility: \(accessibility ? "granted" : "missing")",
            action: nil,
            keyEquivalent: ""
        )
        accessLine.isEnabled = false
        menu.addItem(accessLine)

        let listenLine = NSMenuItem(
            title: "Input Monitoring: \(inputMonitoring ? "granted" : "missing")",
            action: nil,
            keyEquivalent: ""
        )
        listenLine.isEnabled = false
        menu.addItem(listenLine)

        if !listening {
            let hint = NSMenuItem(
                title: permissionHint(accessibility: accessibility, inputMonitoring: inputMonitoring),
                action: nil,
                keyEquivalent: ""
            )
            hint.isEnabled = false
            menu.addItem(hint)

            let path = NSMenuItem(
                title: "App path: \(PermissionPrompts.appLocationForPermissions())",
                action: nil,
                keyEquivalent: ""
            )
            path.isEnabled = false
            menu.addItem(path)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: "Pause switching",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        pause.state = isPaused ? .on : .off
        menu.addItem(pause)

        let loginItem = NSMenuItem(
            title: "Open at login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)

        let convert = NSMenuItem(
            title: "Convert current word - ⌃⌥L",
            action: nil,
            keyEquivalent: ""
        )
        convert.isEnabled = false
        menu.addItem(convert)
        menu.addItem(.separator())

        menu.addItem(layoutItem(language: .en))
        menu.addItem(layoutItem(language: .sv))
        menu.addItem(layoutItem(language: .ru))
        if let name = catalog.currentLayoutName() {
            let current = NSMenuItem(title: "Active layout: \(name)", action: nil, keyEquivalent: "")
            current.isEnabled = false
            menu.addItem(current)
        }
        menu.addItem(.separator())

        if !accessibility {
            let access = NSMenuItem(
                title: "Grant Accessibility…",
                action: #selector(openAccessibility),
                keyEquivalent: ""
            )
            access.target = self
            menu.addItem(access)
        }

        if !listening {
            let listen = NSMenuItem(
                title: "Grant Input Monitoring…",
                action: #selector(openInputMonitoring),
                keyEquivalent: ""
            )
            listen.target = self
            menu.addItem(listen)

            let retry = NSMenuItem(
                title: "Retry keyboard access",
                action: #selector(retryKeyboardAccess),
                keyEquivalent: ""
            )
            retry.target = self
            menu.addItem(retry)
        }

        let reveal = NSMenuItem(
            title: "Show app in Finder",
            action: #selector(revealInFinder),
            keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func refreshStatusTitle() {
        if isPaused {
            statusItem.button?.title = "⏸"
            return
        }
        statusItem.button?.title = displayedLanguage.title
    }

    private func statusTitle(listening: Bool, accessibility: Bool, inputMonitoring: Bool, paused: Bool) -> String {
        if paused && listening {
            return "Status: paused - switching off"
        }
        if listening {
            let layout = catalog.currentLayoutName() ?? "unknown"
            return "Status: listening (\(layout))"
        }
        if !accessibility {
            return "Status: not listening - allow Accessibility"
        }
        if !inputMonitoring {
            return "Status: not listening - allow Input Monitoring"
        }
        return "Status: permissions OK - tap Retry below"
    }

    private func permissionHint(accessibility: Bool, inputMonitoring: Bool) -> String {
        if !accessibility {
            return "In the system dialog, click Open System Settings (not Deny)"
        }
        if !inputMonitoring {
            return "Privacy → Input Monitoring → LangSwitcher ON"
        }
        return "Quit the app, open it again, then Retry keyboard access"
    }

    private func layoutItem(language: Language) -> NSMenuItem {
        let layout = catalog.layout(for: language)
        let name = layout?.name ?? "not installed"
        let enabledNote = layout?.enabled == false ? " - added on first switch" : ""
        let item = NSMenuItem(
            title: "\(language.title): \(name)\(enabledNote)",
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        return item
    }

    private func loadWords() -> [Language: Set<String>] {
        guard let directory = WordListLocations.directory() else {
            os_log_missing_words()
            return [:]
        }
        let words = WordListLoader.load(from: directory)
        return WordListLoader.merge(extraFile: WordListLocations.userExtras(), into: words)
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self = self, let monitor = self.monitor else {
                return
            }
            guard PermissionPrompts.hasAccessibility && PermissionPrompts.hasInputMonitoring else {
                return
            }
            if monitor.start() {
                timer.invalidate()
                self.refreshStatusTitle()
            }
        }
    }

    @objc private func togglePause() {
        guard let monitor = monitor else {
            return
        }
        monitor.isPaused.toggle()
        isPaused = monitor.isPaused
        UserDefaults.standard.set(isPaused, forKey: "isPaused")
        refreshStatusTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !LaunchAtLogin.isEnabled
        do {
            try LaunchAtLogin.setEnabled(enable)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change login item"
            alert.informativeText = """
            \(error.localizedDescription)

            Keep Lang Switcher in Applications (/Applications or ~/Applications).
            You can also add it manually in System Settings → General → Login Items.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        PermissionPrompts.requestAccessibilityPromptIfNeeded()
        PermissionPrompts.openAccessibilitySettings()
        let alert = NSAlert()
        alert.messageText = "Allow Accessibility for this app"
        alert.informativeText = """
        When macOS asks “control this Mac”, click Open System Settings - not Deny.

        In Device Control and Data Access, turn LangSwitcher ON for this file:
        \(PermissionPrompts.appLocationForPermissions())

        If the toggle is already ON but the menu still says missing, remove LangSwitcher with −, add it again with +, then Quit and reopen the app.

        Each rebuild changes the signature; after ./scripts/build-app.sh you must re-allow once.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openInputMonitoring() {
        _ = PermissionPrompts.requestInputMonitoringIfNeeded()
        PermissionPrompts.openInputMonitoringSettings()
    }

    @objc private func retryKeyboardAccess() {
        _ = PermissionPrompts.requestInputMonitoringIfNeeded()
        PermissionPrompts.requestAccessibilityPromptIfNeeded()
        if monitor?.start() == true {
            retryTimer?.invalidate()
        } else {
            scheduleRetry()
        }
    }

    @objc private func revealInFinder() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private func os_log_missing_words() {
    fputs("Lang Switcher could not find word lists (en.txt, sv.txt, ru.txt).\n", stderr)
}

let application = NSApplication.shared
let controller = AppController()
application.delegate = controller
application.setActivationPolicy(.accessory)
application.run()
