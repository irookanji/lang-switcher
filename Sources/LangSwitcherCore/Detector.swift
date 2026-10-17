import Foundation

public enum SwitchDecision: Equatable {
    case stay
    case change(Language)
}

/// Decides whether the current word was typed for a different layout.
///
/// The strings are the same physical keys read through each layout.
/// A switch happens only when one language accepts the text and the
/// language that is active now does not.
public struct LanguageDetector {
    private let indexes: [Language: WordIndex]

    public init(words: [Language: Set<String>]) {
        var indexes: [Language: WordIndex] = [:]
        for (language, list) in words {
            indexes[language] = WordIndex(words: list)
        }
        self.indexes = indexes
    }

    public func decide(
        candidates: [Language: String],
        current: Language,
        wordFinished: Bool
    ) -> SwitchDecision {
        guard let currentText = candidates[current], currentText.count >= 2 else {
            return .stay
        }

        let hits = candidates.map { language, text -> (Language, WordMatch) in
            let match = indexes[language]?.lookup(text) ?? .none
            return (language, match)
        }

        if wordFinished {
            return decideFinished(hits: hits, candidates: candidates, current: current)
        }
        return decidePartial(hits: hits, candidates: candidates, current: current, currentText: currentText)
    }

    private func decideFinished(
        hits: [(Language, WordMatch)],
        candidates: [Language: String],
        current: Language
    ) -> SwitchDecision {
        let words = hits.filter { $0.1 == .word }
        if words.contains(where: { $0.0 == current }) {
            return .stay
        }
        if words.isEmpty {
            return .stay
        }
        if words.count == 1 {
            return .change(words[0].0)
        }

        // Same word in more than one Latin list (e.g. "super" in EN and SV).
        let spellings = Set(words.compactMap { language, _ in candidates[language]?.lowercased() })
        if spellings.count == 1 {
            for language in Language.allCases where words.contains(where: { $0.0 == language && $0.0 != current }) {
                return .change(language)
            }
        }
        return .stay
    }

    private func decidePartial(
        hits: [(Language, WordMatch)],
        candidates: [Language: String],
        current: Language,
        currentText: String
    ) -> SwitchDecision {
        let alive = hits.filter { $0.1 != .none }
        guard alive.count == 1, alive[0].0 != current else {
            return .stay
        }

        let winner = alive[0].0
        guard let winnerText = candidates[winner] else {
            return .stay
        }

        // English and Swedish share the same alphabet. Correct them only at a word
        // boundary so we never delete or retype letters in the middle of a word.
        if script(of: winnerText) != script(of: currentText) {
            return winnerText.count >= 3 ? .change(winner) : .stay
        }
        return .stay
    }

    private func script(of text: String) -> Script {
        let cyrillic = text.contains { character in
            character.unicodeScalars.contains { scalar in
                (0x0400...0x04FF).contains(scalar.value)
            }
        }
        return cyrillic ? .cyrillic : .latin
    }
}

private enum Script {
    case latin
    case cyrillic
}
