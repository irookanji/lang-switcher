import Foundation

public enum WordListLoader {
    /// Loads `en.txt`, `sv.txt`, and `ru.txt` from a directory.
    public static func load(from directory: URL) -> [Language: Set<String>] {
        var words: [Language: Set<String>] = [:]
        for language in Language.allCases {
            let url = directory.appendingPathComponent("\(language.rawValue).txt")
            words[language] = readWords(at: url)
        }
        return words
    }

    /// Merges an optional user file.
    ///
    /// Each line is `en word`, `sv word`, `ru word`, or `* word`.
    /// A leading `*` adds the word to every language so it never forces a switch.
    public static func merge(extraFile url: URL, into words: [Language: Set<String>]) -> [Language: Set<String>] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return words
        }

        var merged = words
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else {
                continue
            }
            let word = String(parts[1]).lowercased()
            if parts[0] == "*" {
                for language in Language.allCases {
                    merged[language, default: []].insert(word)
                }
            } else if let language = Language(rawValue: String(parts[0]).lowercased()) {
                merged[language, default: []].insert(word)
            }
        }
        return merged
    }

    private static func readWords(at url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        var words = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !word.isEmpty {
                words.insert(word)
            }
        }
        return words
    }
}
