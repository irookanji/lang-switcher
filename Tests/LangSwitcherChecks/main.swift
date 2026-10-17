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

private func runLayoutChecks() {
    let catalog = KeyboardCatalog()
    checkEqual(catalog.layout(for: .en)?.id, "com.apple.keylayout.USInternational-PC", "english layout")
    checkEqual(catalog.layout(for: .sv)?.id, "com.apple.keylayout.Swedish-Pro", "swedish layout")
    checkEqual(catalog.layout(for: .ru)?.id, "com.apple.keylayout.Russian", "russian layout")

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
