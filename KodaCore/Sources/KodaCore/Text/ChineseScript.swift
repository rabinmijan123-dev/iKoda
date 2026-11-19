import Foundation

/// Chinese shown in Traditional characters: song titles, artists, albums and lyrics arrive
/// in whichever script the uploader or the lyrics service used, very often Simplified.
///
/// The conversion is Apple's own ICU transform, on the device. It goes character by
/// character, so it does not swap in Taiwanese wording, and a Simplified character with
/// more than one Traditional form gets the common one. Only Han characters change:
/// English, numbers, IDs and URLs pass through untouched. Text with kana is Japanese and
/// is left alone, since Japanese kanji are not Simplified Chinese even where they look it.
public enum ChineseScript {
    /// `text` in Traditional characters, or `text` itself when there is nothing to change.
    public static func traditional(_ text: String) -> String {
        guard hasHan(text), !hasKana(text) else { return text }
        return transform(text, ids: ["Hans-Hant", "Simplified-Traditional"])
    }

    /// `text` in Simplified characters: how most lyrics services index Chinese songs.
    public static func simplified(_ text: String) -> String {
        guard hasHan(text), !hasKana(text) else { return text }
        return transform(text, ids: ["Hant-Hans", "Traditional-Simplified"])
    }

    /// Lyrics in Traditional characters, judged as a whole song: one line of kanji alone
    /// can't say whether it is Japanese or Chinese, the song can.
    public static func traditional(_ lyrics: Lyrics) -> Lyrics {
        switch lyrics {
        case .plain(let text):
            return .plain(traditional(text))
        case .synced(let lines):
            let all = lines.map(\.text) + lines.flatMap { ($0.words + $0.background).map(\.text) }
            guard all.contains(where: hasHan), !all.contains(where: hasKana) else { return lyrics }
            return .synced(lines.map { line in
                var line = line
                line.text = convert(line.text)
                line.words = line.words.map { word in
                    var word = word
                    word.text = convert(word.text)
                    return word
                }
                line.background = line.background.map { word in
                    var word = word
                    word.text = convert(word.text)
                    return word
                }
                return line
            })
        }
    }

    /// The song has been judged Chinese already: no kana check per line.
    private static func convert(_ text: String) -> String {
        hasHan(text) ? transform(text, ids: ["Hans-Hant", "Simplified-Traditional"]) : text
    }

    /// Pages repeat the same titles and artists, and every string a parser reads comes
    /// through here: each conversion is done once. NSCache is safe across threads.
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 4000
        return cache
    }()

    private static func transform(_ text: String, ids: [String]) -> String {
        #if canImport(Darwin)
        let key = (ids[0] + "|" + text) as NSString
        if let hit = cache.object(forKey: key) { return hit as String }
        for id in ids {
            if let converted = text.applyingTransform(StringTransform(id), reverse: false) {
                cache.setObject(converted as NSString, forKey: key)
                return converted
            }
        }
        #endif
        return text
    }

    /// CJK ideographs, with their extensions and compatibility forms.
    static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: true
            default: false
            }
        }
    }

    /// Hiragana and katakana. The katakana middle dot (・) is left out: Chinese uses it
    /// between the parts of a transliterated name.
    static func hasKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x30FB: false
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: true
            default: false
            }
        }
    }
}
