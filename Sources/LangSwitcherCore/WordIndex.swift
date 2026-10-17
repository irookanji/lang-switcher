import Foundation

enum WordMatch: Equatable {
    case none
    case prefix
    case word
}

/// Dictionary lookup that can tell a finished word from a prefix of a longer one.
struct WordIndex {
    private let words: Set<String>
    private let prefixes: Set<String>

    init(words: Set<String>) {
        self.words = words
        var prefixes = Set<String>()
        prefixes.reserveCapacity(words.count * 8)
        for word in words {
            var prefix = ""
            prefix.reserveCapacity(word.count)
            for character in word {
                prefix.append(character)
                prefixes.insert(prefix)
            }
        }
        self.prefixes = prefixes
    }

    func lookup(_ text: String) -> WordMatch {
        let folded = text.lowercased()
        guard prefixes.contains(folded) else {
            return .none
        }
        if words.contains(folded) {
            return .word
        }
        return .prefix
    }
}
