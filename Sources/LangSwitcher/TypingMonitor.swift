import AppKit
import ApplicationServices
import Carbon
import Foundation
import os.log

import LangSwitcherCore

private let switchLog = OSLog(subsystem: "local.langswitcher", category: "switch")

private let boundaryKeyCodes: Set<UInt16> = [36, 48, 49, 76]
private let resetKeyCodes: Set<UInt16> = [53, 115, 116, 117, 119, 121, 123, 124, 125, 126]
private let deleteKeyCode: UInt16 = 51
private let manualConvertKeyCode: UInt16 = 37
private let syntheticEventMark: Int64 = 0x4C_53_57
private let maximumWordKeys = 40

/// Watches typing and rewrites a word when it belongs to another layout.
final class TypingMonitor {
    private let detector: LanguageDetector
    private let catalog: KeyboardCatalog
    private var strokes: [Keystroke] = []
    private var active: Language
    private var keyboardType: UInt32
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var ignoreSourceChangesUntil = Date.distantPast
    private var sourceObserver: NSObjectProtocol?
    /// Characters visible in the focused field for the current word.
    private var composedText = ""

    var autoSwitch = true
    var onLanguageChange: ((Language) -> Void)?
    var onPauseChange: ((Bool) -> Void)?

    var isPaused: Bool {
        get { !autoSwitch }
        set {
            autoSwitch = !newValue
            if newValue {
                clearWord()
            }
            onPauseChange?(newValue)
        }
    }

    var isListening: Bool {
        tap != nil
    }

    init(detector: LanguageDetector, catalog: KeyboardCatalog) {
        self.detector = detector
        self.catalog = catalog
        self.active = catalog.currentLanguage() ?? .en
        self.keyboardType = UInt32(LMGetKbdType())
        observeLayoutChanges()
    }

    deinit {
        if let sourceObserver = sourceObserver {
            DistributedNotificationCenter.default().removeObserver(sourceObserver)
        }
    }

    func start() -> Bool {
        if tap != nil {
            return true
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<TypingMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            return false
        }

        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMark {
            return Unmanaged.passUnretained(event)
        }

        if type != .keyDown {
            clearWord()
            return Unmanaged.passUnretained(event)
        }

        return handleKeyDown(event, proxy: proxy)
    }

    private func handleKeyDown(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        syncActiveWithSystemIfNeeded()

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let reportedType = UInt32(event.getIntegerValueField(.keyboardEventKeyboardType))
        if reportedType != 0 {
            keyboardType = reportedType
        }

        if isManualConvert(flags: flags, keyCode: keyCode) {
            cycleLayout(proxy: proxy)
            return nil
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            clearWord()
            return Unmanaged.passUnretained(event)
        }

        if keyCode == deleteKeyCode {
            if !strokes.isEmpty {
                strokes.removeLast()
                syncComposedText()
            }
            return Unmanaged.passUnretained(event)
        }

        if resetKeyCodes.contains(keyCode) {
            clearWord()
            return Unmanaged.passUnretained(event)
        }

        if boundaryKeyCodes.contains(keyCode) {
            let rewrote = autoSwitch && switchIfNeeded(wordFinished: true, proxy: proxy)
            clearWord()
            if rewrote {
                // Post the space after the corrected word. Returning it as well
                // would deliver the space before those replacement events.
                event.tapPostEvent(proxy)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if isPaused {
            return Unmanaged.passUnretained(event)
        }

        if strokes.count >= maximumWordKeys {
            clearWord()
            return Unmanaged.passUnretained(event)
        }

        let stroke = Keystroke(
            keyCode: keyCode,
            modifiers: CarbonModifiers.from(
                shift: flags.contains(.maskShift),
                option: flags.contains(.maskAlternate),
                capsLock: flags.contains(.maskAlphaShift),
                control: false,
                command: false
            )
        )
        strokes.append(stroke)

        if switchIfNeeded(wordFinished: false, proxy: proxy) {
            return nil
        }
        syncComposedText()
        return Unmanaged.passUnretained(event)
    }

    /// Returns true when the on-screen word was rewritten.
    private func switchIfNeeded(wordFinished: Bool, proxy: CGEventTapProxy) -> Bool {
        guard !strokes.isEmpty else {
            return false
        }

        let displayLanguage = systemLanguage()
        let texts = translations(of: strokes)
        guard let current = texts[displayLanguage], !current.deadKeyPending else {
            return false
        }

        if wordFinished && composedText.isEmpty {
            composedText = current.text
        }

        let decision = detector.decide(
            candidates: texts.mapValues { $0.text },
            current: displayLanguage,
            wordFinished: wordFinished
        )
        guard case .change(let target) = decision, let updated = texts[target] else {
            return false
        }

        let deleteCount: Int
        if wordFinished {
            deleteCount = composedText.count
        } else {
            let visible = translations(of: Array(strokes.dropLast()))[displayLanguage]?.text ?? ""
            composedText = visible
            deleteCount = visible.count
        }

        guard activate(target) else {
            return false
        }

        let glyphsChanged = current.text != updated.text
        if glyphsChanged {
            replace(deleting: deleteCount, with: updated.text, proxy: proxy)
            composedText = updated.text
        } else {
            composedText = current.text
        }
        if glyphsChanged {
            return true
        }
        return wordFinished && target != displayLanguage
    }

    private func systemLanguage() -> Language {
        catalog.currentLanguage() ?? active
    }

    private func syncActiveWithSystemIfNeeded() {
        guard Date() >= ignoreSourceChangesUntil else {
            return
        }
        guard let system = catalog.currentLanguage() else {
            return
        }
        guard system != active else {
            return
        }
        clearWord()
        active = system
        onLanguageChange?(system)
    }

    private func clearWord() {
        strokes.removeAll()
        composedText = ""
    }

    private func syncComposedText() {
        guard !strokes.isEmpty else {
            composedText = ""
            return
        }
        composedText = translations(of: strokes)[systemLanguage()]?.text ?? composedText
    }

    private func cycleLayout(proxy: CGEventTapProxy) {
        let order = Language.allCases
        let currentLanguage = systemLanguage()
        guard let index = order.firstIndex(of: currentLanguage) else {
            return
        }
        let target = order[(index + 1) % order.count]
        let texts = translations(of: strokes)
        let currentText = texts[currentLanguage]?.text ?? ""
        let updatedText = texts[target]?.text ?? currentText
        if !strokes.isEmpty && currentText != updatedText {
            replace(deleting: composedText.count, with: updatedText, proxy: proxy)
            composedText = updatedText
        }
        activate(target)
    }

    private func translations(of strokes: [Keystroke]) -> [Language: LayoutTranslation] {
        var texts: [Language: LayoutTranslation] = [:]
        for language in Language.allCases {
            guard let layout = catalog.layout(for: language) else {
                continue
            }
            let translator = LayoutTranslator(layoutData: layout.layoutData, keyboardType: keyboardType)
            texts[language] = translator.translate(strokes)
        }
        return texts
    }

    @discardableResult
    private func activate(_ language: Language) -> Bool {
        if catalog.currentLanguage() != language {
            ignoreSourceChangesUntil = Date().addingTimeInterval(0.4)
            guard catalog.select(language) else {
                return false
            }
            os_log(
                "layout %{public}@ -> %{public}@",
                log: switchLog,
                type: .info,
                active.rawValue,
                language.rawValue
            )
        }
        active = language
        onLanguageChange?(language)
        return true
    }

    private func replace(deleting count: Int, with text: String, proxy: CGEventTapProxy) {
        guard count > 0 || !text.isEmpty else {
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<count {
            postKey(virtualKey: deleteKeyCode, keyDown: true, source: source, proxy: proxy)
            postKey(virtualKey: deleteKeyCode, keyDown: false, source: source, proxy: proxy)
        }
        for character in text {
            postUnicode(character, source: source, proxy: proxy)
        }
    }

    private func postKey(virtualKey: UInt16, keyDown: Bool, source: CGEventSource?, proxy: CGEventTapProxy) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            return
        }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMark)
        event.tapPostEvent(proxy)
    }

    private func postUnicode(_ character: Character, source: CGEventSource?, proxy: CGEventTapProxy) {
        var units = Array(String(character).utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            return
        }
        down.flags = []
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMark)
        down.tapPostEvent(proxy)

        guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }
        up.flags = []
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMark)
        up.tapPostEvent(proxy)
    }

    private func isManualConvert(flags: CGEventFlags, keyCode: UInt16) -> Bool {
        guard keyCode == manualConvertKeyCode else {
            return false
        }
        let relevant = flags.intersection([.maskControl, .maskAlternate, .maskCommand])
        return relevant.contains(.maskControl) && relevant.contains(.maskAlternate) && !relevant.contains(.maskCommand)
    }

    private func observeLayoutChanges() {
        let name = NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        sourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.layoutChangedOutside()
        }
    }

    private func layoutChangedOutside() {
        if Date() < ignoreSourceChangesUntil {
            return
        }
        guard let language = catalog.currentLanguage() else {
            return
        }
        clearWord()
        active = language
        onLanguageChange?(language)
    }
}

enum WordListLocations {
    static func directory() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources)
            candidates.append(resources.appendingPathComponent("wordlists"))
        }
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        candidates.append(current.appendingPathComponent("wordlists"))
        candidates.append(current)

        for candidate in candidates {
            let marker = candidate.appendingPathComponent("en.txt")
            if fileManager.fileExists(atPath: marker.path) {
                return candidate
            }
        }
        return nil
    }

    static func userExtras() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("LangSwitcher", isDirectory: true)
            .appendingPathComponent("words.txt")
    }
}

enum PermissionPrompts {
    /// Shows the system sheet only when Accessibility is still missing.
    static func requestAccessibilityPromptIfNeeded() {
        guard !hasAccessibility else {
            return
        }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestInputMonitoringIfNeeded() -> Bool {
        if hasInputMonitoring {
            return true
        }
        return CGRequestListenEventAccess()
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        openFirst(urls)
    }

    /// Short path shown in the menu so Privacy lists can be matched to this build.
    static func appLocationForPermissions() -> String {
        Bundle.main.bundleURL.path
    }

    static func openInputMonitoringSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ]
        openFirst(urls)
    }

    private static func openFirst(_ urls: [String]) {
        for raw in urls {
            guard let url = URL(string: raw) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
