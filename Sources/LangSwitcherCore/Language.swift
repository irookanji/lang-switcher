import Foundation

/// Keyboard language this switcher can select.
public enum Language: String, CaseIterable {
    case en
    case sv
    case ru

    /// Short label shown in the menu bar.
    public var title: String {
        switch self {
        case .en:
            return "EN"
        case .sv:
            return "SV"
        case .ru:
            return "RU"
        }
    }

    /// Layouts to prefer when several inputs share a primary language.
    /// Enabled layouts still win over this list.
    var preferredSourceIDs: [String] {
        switch self {
        case .en:
            return [
                "com.apple.keylayout.USInternational-PC",
                "com.apple.keylayout.US",
                "com.apple.keylayout.ABC"
            ]
        case .sv:
            return [
                "com.apple.keylayout.Swedish-Pro",
                "com.apple.keylayout.Swedish",
                "com.apple.keylayout.SwedishSami-PC"
            ]
        case .ru:
            return [
                "com.apple.keylayout.Russian",
                "com.apple.keylayout.RussianWin",
                "com.apple.keylayout.Russian-Phonetic"
            ]
        }
    }
}
