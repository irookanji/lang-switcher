import Carbon
import Foundation

import LangSwitcherCore

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
    if condition {
        return
    }
    failures += 1
    fputs("FAIL \(message)\n", stderr)
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    check(actual == expected, "\(message) — expected \(expected), got \(actual)")
}

private func wordListDirectory() -> URL {
    URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("wordlists")
}

private func runDetectorChecks() {
    let detector = LanguageDetector(words: [
        .en: ["hello", "the", "for", "man", "in", "ghost"],
        .sv: ["och", "för", "på", "man", "in", "hej"],
        .ru: ["привет", "как", "дела"]
    ])

    checkEqual(
        detector.decide(
            candidates: [.en: "ghb", .sv: "ghb", .ru: "при"],
            current: .en,
            wordFinished: false
        ),
        .change(.ru),
        "early Russian switch"
    )
    checkEqual(
        detector.decide(
            candidates: [.en: "gh", .sv: "gh", .ru: "пр"],
            current: .en,
            wordFinished: false
        ),
        .stay,
        "shared prefix stays"
    )
    checkEqual(
        detector.decide(
            candidates: [.en: "hello", .sv: "hello", .ru: "руддщ"],
            current: .ru,
            wordFinished: true
        ),
        .change(.en),
        "hello on Russian layout"
    )
    checkEqual(
        detector.decide(
            candidates: [.en: "f;r", .sv: "för", .ru: "ажк"],
            current: .en,
            wordFinished: false
        ),
        .stay,
        "för waits for a word boundary"
    )
    checkEqual(
        detector.decide(
            candidates: [.en: "f;r", .sv: "för", .ru: "ажк"],
            current: .en,
            wordFinished: true
        ),
        .change(.sv),
        "för typed on the US layout"
    )
    checkEqual(
        detector.decide(
            candidates: [.en: "man", .sv: "man", .ru: "ьфт"],
            current: .en,
            wordFinished: true
        ),
        .stay,
        "ambiguous man stays"
    )

    let words = WordListLoader.load(from: wordListDirectory())
    check((words[.en]?.count ?? 0) > 10_000, "english list loaded")
    check((words[.sv]?.count ?? 0) > 10_000, "swedish list loaded")
    check((words[.ru]?.count ?? 0) > 10_000, "russian list loaded")

    let real = LanguageDetector(words: words)
    checkEqual(
        real.decide(
            candidates: [.en: "ghbdtn", .sv: "ghbdtn", .ru: "привет"],
            current: .en,
            wordFinished: false
        ),
        .change(.ru),
        "привет"
    )
    checkEqual(
        real.decide(
            candidates: [.en: "hello", .sv: "hello", .ru: "руддщ"],
            current: .ru,
            wordFinished: true
        ),
        .change(.en),
        "hello"
    )
    checkEqual(
        real.decide(
            candidates: [.en: "och", .sv: "och", .ru: "офп"],
            current: .en,
            wordFinished: true
        ),
        .change(.sv),
        "och"
    )
    checkEqual(
        real.decide(
            candidates: [.en: "the", .sv: "the", .ru: "еру"],
            current: .sv,
            wordFinished: true
        ),
        .change(.en),
        "the"
    )
    checkEqual(
        real.decide(
            candidates: [.en: "in", .sv: "in", .ru: "шт"],
            current: .en,
            wordFinished: true
        ),
        .stay,
        "in is shared"
    )
    checkEqual(
        real.decide(
            candidates: [.en: "super", .sv: "super", .ru: "ыгзук"],
            current: .ru,
            wordFinished: true
        ),
        .change(.en),
        "super from Russian layout -> English"
    )

    let kept = ["VS", "vs", "Db", "db", "yf", "yb", "gf", "gp"]
    let keptRussian = ["мы", "мы", "ви", "ви", "на", "ни", "па", "пз"]
    for pair in zip(kept, keptRussian) {
        let candidates: [Language: String] = [.en: pair.0, .sv: pair.0, .ru: pair.1]
        checkEqual(
            real.decide(candidates: candidates, current: .en, wordFinished: true),
            .stay,
            "\(pair.0) stays Latin on US"
        )
        checkEqual(
            real.decide(candidates: candidates, current: .sv, wordFinished: true),
            .stay,
            "\(pair.0) stays Latin on Swedish"
        )
        checkEqual(
            real.decide(candidates: candidates, current: .ru, wordFinished: true),
            .stay,
            "\(pair.1) stays Cyrillic on Russian"
        )
    }

    let claimed = LanguageDetector(words: [
        .en: ["vs", "db", "yf", "yb", "gf", "gp", "hello"],
        .sv: [],
        .ru: []
    ])
    checkEqual(
        claimed.decide(
            candidates: [.en: "vs", .sv: "vs", .ru: "мы"],
            current: .ru,
            wordFinished: true
        ),
        .stay,
        "мы stays even when vs is listed as English"
    )
    checkEqual(
        real.decide(
            candidates: [.en: "yt", .sv: "yt", .ru: "не"],
            current: .en,
            wordFinished: true
        ),
        .change(.ru),
        "other two-letter Russian words still switch"
    )
}

private func letterKeys(on translator: LayoutTranslator) -> [Character: UInt16] {
    var map: [Character: UInt16] = [:]
    for code: UInt16 in 0...127 {
        let text = translator.translate([Keystroke(keyCode: code, modifiers: 0)]).text
        if text.count == 1, let character = text.first, character.isLetter {
            map[character] = code
        }
    }
    return map
}

private func typed(_ word: String, on source: LayoutTranslator, readBy destination: LayoutTranslator) -> String {
    let map = letterKeys(on: source)
    let strokes = word.map { character -> Keystroke in
        Keystroke(keyCode: map[character] ?? 0, modifiers: 0)
    }
    return destination.translate(strokes).text
}

private func checkLayout(
    _ catalog: KeyboardCatalog,
    language: Language,
    preferredIDs: [String],
    label: String
) {
    guard let id = catalog.layout(for: language)?.id else {
        check(false, "\(label) layout not installed")
        return
    }
    check(
        preferredIDs.contains(id),
        "\(label) layout — expected one of \(preferredIDs), got \(id)"
    )
}

private func runLayoutChecks() {
    let catalog = KeyboardCatalog()
    checkLayout(
        catalog,
        language: .en,
        preferredIDs: [
            "com.apple.keylayout.USInternational-PC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.ABC"
        ],
        label: "english"
    )
    checkLayout(
        catalog,
        language: .sv,
        preferredIDs: [
            "com.apple.keylayout.Swedish-Pro",
            "com.apple.keylayout.Swedish",
            "com.apple.keylayout.SwedishSami-PC"
        ],
        label: "swedish"
    )
    checkLayout(
        catalog,
        language: .ru,
        preferredIDs: [
            "com.apple.keylayout.Russian",
            "com.apple.keylayout.RussianWin",
            "com.apple.keylayout.Russian-Phonetic"
        ],
        label: "russian"
    )

    guard
        let english = catalog.layout(for: .en),
        let swedish = catalog.layout(for: .sv),
        let russian = catalog.layout(for: .ru)
    else {
        check(false, "layouts available")
        return
    }

    let keyboardType = UInt32(LMGetKbdType())
    let englishKeys = LayoutTranslator(layoutData: english.layoutData, keyboardType: keyboardType)
    let swedishKeys = LayoutTranslator(layoutData: swedish.layoutData, keyboardType: keyboardType)
    let russianKeys = LayoutTranslator(layoutData: russian.layoutData, keyboardType: keyboardType)

    checkEqual(typed("привет", on: russianKeys, readBy: englishKeys), "ghbdtn", "привет on US")
    checkEqual(typed("vs", on: englishKeys, readBy: russianKeys), "мы", "vs on Russian")
    checkEqual(typed("db", on: englishKeys, readBy: russianKeys), "ви", "db on Russian")
    checkEqual(typed("yf", on: englishKeys, readBy: russianKeys), "на", "yf on Russian")
    checkEqual(typed("yb", on: englishKeys, readBy: russianKeys), "ни", "yb on Russian")
    checkEqual(typed("gf", on: englishKeys, readBy: russianKeys), "па", "gf on Russian")
    checkEqual(typed("gp", on: englishKeys, readBy: russianKeys), "пз", "gp on Russian")
    checkEqual(typed("hello", on: englishKeys, readBy: russianKeys), "руддщ", "hello on Russian")
    checkEqual(typed("för", on: swedishKeys, readBy: englishKeys), "f;r", "för on US")
    checkEqual(typed("på", on: swedishKeys, readBy: englishKeys), "p[", "på on US")
    checkEqual(typed("och", on: swedishKeys, readBy: englishKeys), "och", "och is the same keys")
}

runDetectorChecks()
runLayoutChecks()

if failures == 0 {
    fputs("All checks passed.\n", stdout)
    exit(0)
}
fputs("\(failures) check(s) failed.\n", stderr)
exit(1)
