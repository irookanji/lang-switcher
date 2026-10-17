import Carbon
import Foundation

public struct Keystroke: Equatable {
    public let keyCode: UInt16
    public let modifiers: UInt32

    public init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct LayoutTranslation: Equatable {
    public let text: String
    public let deadKeyPending: Bool

    public init(text: String, deadKeyPending: Bool) {
        self.text = text
        self.deadKeyPending = deadKeyPending
    }
}

/// Turns physical keystrokes into the text a keyboard layout would produce.
public struct LayoutTranslator {
    private let layoutData: Data
    private let keyboardType: UInt32

    public init(layoutData: Data, keyboardType: UInt32) {
        self.layoutData = layoutData
        self.keyboardType = keyboardType
    }

    public func translate(_ strokes: [Keystroke]) -> LayoutTranslation {
        var deadKeyState: UInt32 = 0
        var text = ""

        for stroke in strokes {
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            let status = layoutData.withUnsafeBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else {
                    return OSStatus(paramErr)
                }
                let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
                return UCKeyTranslate(
                    layout,
                    stroke.keyCode,
                    UInt16(kUCKeyActionDown),
                    stroke.modifiers,
                    keyboardType,
                    0,
                    &deadKeyState,
                    8,
                    &length,
                    &chars
                )
            }
            if status == noErr && length > 0 {
                text += String(utf16CodeUnits: chars, count: length)
            }
        }

        return LayoutTranslation(text: text, deadKeyPending: deadKeyState != 0)
    }
}

public enum CarbonModifiers {
    /// UCKeyTranslate expects Carbon modifier bits shifted down by 8.
    public static func from(shift: Bool, option: Bool, capsLock: Bool, control: Bool, command: Bool) -> UInt32 {
        var modifiers: UInt32 = 0
        if shift {
            modifiers |= UInt32(shiftKey >> 8)
        }
        if option {
            modifiers |= UInt32(optionKey >> 8)
        }
        if capsLock {
            modifiers |= UInt32(alphaLock >> 8)
        }
        if control {
            modifiers |= UInt32(controlKey >> 8)
        }
        if command {
            modifiers |= UInt32(cmdKey >> 8)
        }
        return modifiers
    }
}
