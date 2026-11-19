import Foundation
import Testing
@testable import KodaCore

@Suite struct ChineseScriptTests {
    @Test func simplifiedReadsAsTraditional() {
        #expect(ChineseScript.traditional("周杰伦") == "周杰倫")
        #expect(ChineseScript.traditional("艾薇儿・拉维妮") == "艾薇兒・拉維妮")
        #expect(ChineseScript.traditional("稻香 - 周杰伦 (官方版)") == "稻香 - 周杰倫 (官方版)")
    }

    /// Characters both scripts share stay as they are: 杰 is not rewritten as 傑.
    @Test func keepsSharedCharacters() {
        #expect(ChineseScript.traditional("台湾的歌") == "台灣的歌")
        #expect(ChineseScript.traditional("和你见面") == "和你見面")
    }

    /// Text already in Traditional characters is left exactly as it is.
    @Test func leavesTraditionalAlone() {
        #expect(ChineseScript.traditional("周杰倫") == "周杰倫")
        #expect(ChineseScript.traditional("我在台北等你") == "我在台北等你")
        #expect(ChineseScript.traditional("以後的以後") == "以後的以後")
    }

    @Test func traditionalReadsAsSimplified() {
        #expect(ChineseScript.simplified("周杰倫") == "周杰伦")
    }

    @Test func leavesEverythingButHanAlone() {
        #expect(ChineseScript.traditional("Blinding Lights") == "Blinding Lights")
        #expect(ChineseScript.traditional("dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(ChineseScript.traditional("사랑해") == "사랑해")
    }

    /// 学 is Simplified in Chinese but ordinary Japanese: kana mark the text as Japanese.
    @Test func leavesJapaneseAlone() {
        #expect(ChineseScript.traditional("学校へ行こう") == "学校へ行こう")
    }

    @Test func jsonStringsReadAsTraditional() throws {
        let json = try JSON(data: Data(#"{"title": {"runs": [{"text": "稻香"}, {"text": " • 周杰伦"}]}, "videoId": "abc123"}"#.utf8))
        #expect(json["title"].text == "稻香 • 周杰倫")
        #expect(json["videoId"].string == "abc123")
        #expect(json.strings("text") == ["稻香", " • 周杰倫"])
    }

    @Test func verbatimJSONKeepsItsScript() throws {
        let json = try JSON(verbatimData: Data(#"{"lyrics": "我爱你", "list": [{"line": {"text": "学"}}]}"#.utf8))
        #expect(json["lyrics"].string == "我爱你")
        #expect(json["list"].array.first?["line"]["text"].string == "学")
        #expect(json.first("line")["text"].string == "学")
        #expect(json.strings("text") == ["学"])
    }

    @Test func chineseLyricsReadAsTraditional() {
        let lyrics = Lyrics.synced(Lyrics.parseLRC("[00:10.00]<00:10.00>我 <00:10.50>爱你\n[00:20.00]学会"))
        guard case .synced(let lines) = ChineseScript.traditional(lyrics) else {
            Issue.record("expected synced lyrics")
            return
        }
        #expect(lines.map(\.text) == ["我 愛你", "學會"])
        #expect(lines[0].words.map(\.text) == ["我", "愛你"])
        #expect(ChineseScript.traditional(Lyrics.plain("我爱你")) == .plain("我愛你"))
    }

    /// A Japanese song is judged as a whole: its lines of kanji alone stay as they are.
    @Test func japaneseLyricsStayAsTheyAre() {
        let lyrics = Lyrics.synced(Lyrics.parseLRC("[00:10.00]学園\n[00:20.00]君の名前を呼んだ"))
        #expect(ChineseScript.traditional(lyrics) == lyrics)
    }
}
