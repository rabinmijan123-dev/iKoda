import Foundation

/// Chinese shown in Traditional characters, the way Taiwan writes it: song titles, artists,
/// albums and lyrics arrive in whichever script the uploader or the lyrics service used,
/// very often Simplified.
///
/// The conversion is OpenCC's, on the device (see `OpenCCData`): whole words before single
/// characters, so 头发 becomes 頭髮 and 以后 以後 while 皇后 stays 皇后, then Taiwanese
/// wording and the 台/臺 rules (台北, 電視台, but 臺灣大學).
///
/// Only text that is plainly Simplified is converted: text with at least one character that
/// Traditional Chinese doesn't have, told by Big5 (code page 950), the Traditional character
/// set. Text already in Traditional characters is left exactly as it is. Only Han characters
/// change: English, numbers, IDs and URLs pass through untouched. Text with kana is Japanese
/// and is left alone, since Japanese kanji are not Simplified Chinese.
public enum ChineseScript {
    /// `text` in Traditional characters, or `text` itself when it isn't Simplified Chinese.
    public static func traditional(_ text: String) -> String {
        guard hasHan(text), !hasKana(text), hasSimplifiedOnly(text) else { return text }
        return convert(text)
    }

    /// `text` in Simplified characters: how most lyrics services index Chinese songs.
    public static func simplified(_ text: String) -> String {
        guard hasHan(text), !hasKana(text) else { return text }
        let key = "s|" + text as NSString
        if let hit = cache.object(forKey: key) { return hit as String }
        var converted = text
        #if canImport(Darwin)
        converted = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
        #endif
        cache.setObject(converted as NSString, forKey: key)
        return converted
    }

    /// Lyrics in Traditional characters, judged as a whole song: one line of kanji alone
    /// can't say whether it is Japanese or Chinese, nor one line of shared characters whether
    /// it is Simplified or Traditional; the song can.
    public static func traditional(_ lyrics: Lyrics) -> Lyrics {
        switch lyrics {
        case .plain(let text):
            return .plain(traditional(text))
        case .synced(let lines):
            let all = lines.map(\.text) + lines.flatMap { ($0.words + $0.background).map(\.text) }
            guard all.contains(where: hasHan), !all.contains(where: hasKana), all.contains(where: hasSimplifiedOnly) else {
                return lyrics
            }
            return .synced(lines.map { line in
                var line = line
                line.text = convert(line.text)
                line.words = convert(line.words)
                line.background = convert(line.background)
                return line
            })
        }
    }

    /// A line's words converted together, so a word split over syllables (头 发) is still
    /// read as one (頭髮). When the conversion changes the length, word by word instead.
    private static func convert(_ words: [LyricWord]) -> [LyricWord] {
        guard !words.isEmpty else { return words }
        let joined = words.map(\.text).joined()
        let converted = Array(convert(joined).unicodeScalars)
        guard converted.count == joined.unicodeScalars.count else {
            return words.map { word in
                var word = word
                word.text = convert(word.text)
                return word
            }
        }
        var index = 0
        return words.map { word in
            var word = word
            let count = word.text.unicodeScalars.count
            var text = String.UnicodeScalarView()
            text.append(contentsOf: converted[index..<index + count])
            word.text = String(text)
            index += count
            return word
        }
    }

    /// Text judged Simplified, in Taiwan Traditional.
    private static func convert(_ text: String) -> String {
        guard hasHan(text) else { return text }
        let key = "t|" + text as NSString
        if let hit = cache.object(forKey: key) { return hit as String }
        let converted = Tables.taiwan.convert(Tables.traditional.convert(text))
        cache.setObject(converted as NSString, forKey: key)
        return converted
    }

    /// Built on first use, off whichever thread asks first; read-only after that.
    private enum Tables {
        /// Simplified to Traditional. 杰 is a character of its own in Traditional too, the one
        /// most names use (周杰倫, 張杰): it stays, though words like 杰出 still become 傑出.
        static let traditional = PhraseTable([OpenCCData.stCharacters, OpenCCData.stPhrases, OpenCCData.cnQuality, "杰\t杰"])
        /// Traditional to Taiwan's characters and wording.
        static let taiwan = PhraseTable([OpenCCData.twVariants, OpenCCData.twPhrasesCustom, OpenCCData.tw2QualityPhrases,
                                         OpenCCData.tw2Tai, OpenCCData.tw2Quality])
    }

    /// Pages repeat the same titles and artists, and every string a parser reads comes
    /// through here: each conversion is done once. NSCache is safe across threads.
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 4000
        return cache
    }()

    #if canImport(Darwin)
    /// Big5 as Windows has it (code page 950): the Traditional character set.
    private static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosChineseTrad.rawValue)))
    #endif

    /// Whether `text` has a Han character Traditional Chinese doesn't use: 伦, 爱, 学, 们.
    static func hasSimplifiedOnly(_ text: String) -> Bool {
        #if canImport(Darwin)
        return text.unicodeScalars.contains { scalar in
            isHan(scalar) && !String(scalar).canBeConverted(to: big5)
        }
        #else
        return false
        #endif
    }

    /// CJK ideographs, with their extensions and compatibility forms.
    static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHan)
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: true
        default: false
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

/// One OpenCC conversion step: its dictionaries merged into one table, later ones winning,
/// applied by longest match from the left, as OpenCC does.
struct PhraseTable: Sendable {
    private let entries: [String: String]
    private let longest: Int

    /// Dictionaries of `source<tab>target` lines (a space also separates).
    init(_ dictionaries: [String]) {
        var entries: [String: String] = [:]
        var longest = 1
        for dictionary in dictionaries {
            for line in dictionary.split(whereSeparator: \.isNewline) {
                let entry = line.trimmingCharacters(in: .whitespaces)
                guard let separator = entry.firstIndex(of: "\t") ?? entry.firstIndex(of: " ") else { continue }
                let source = String(entry[..<separator])
                let target = String(entry[entry.index(after: separator)...])
                guard !source.isEmpty else { continue }
                entries[source] = target
                longest = max(longest, source.unicodeScalars.count)
            }
        }
        self.entries = entries
        self.longest = longest
    }

    func convert(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            var matched = false
            var length = min(longest, scalars.count - index)
            while length > 0 {
                var candidate = String.UnicodeScalarView()
                candidate.append(contentsOf: scalars[index..<index + length])
                if let target = entries[String(candidate)] {
                    out.append(contentsOf: target.unicodeScalars)
                    index += length
                    matched = true
                    break
                }
                length -= 1
            }
            if !matched {
                out.append(scalars[index])
                index += 1
            }
        }
        return String(out)
    }
}
