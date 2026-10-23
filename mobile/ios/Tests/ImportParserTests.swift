import XCTest
@testable import NIVQOProtocol

final class ImportParserTests: XCTestCase {
    func testQuotedPasswordsAndNoSessionURLs() throws {
        let csv = "name,url,username,password\r\nWork,https://example.com,user,\"a,b\"\r\nUnsafe,javascript:alert(1),user,bad\r\nEmbedded,https://user:secret@example.com,user,bad\r\n"
        let result = try ImportParser.parse(Data(csv.utf8), passwords: true, spaceID: "work")
        XCTAssertEqual(result.rows.count, 1); XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(result.rows[0].password, "a,b"); XCTAssertEqual(result.spaceID, "work")
    }
    func testQuotedNewlinesAndQuotes() throws {
        let rows = try ImportParser.csv("url,username,password\nhttps://example.com,u,\"first\nsecond\"\"quote\"\n")
        XCTAssertEqual(rows[1][2], "first\nsecond\"quote")
        XCTAssertThrowsError(try ImportParser.csv("url,username,password\n\"unfinished"))
    }
    func testBookmarksHTMLNeverExecutesContent() throws {
        let html = "<DL><A HREF=\"https://example.com/?a=1&amp;b=2\">Work &amp; home</A><A HREF='javascript:alert(1)'>Bad</A></DL>"
        let result = try ImportParser.parse(Data(html.utf8), passwords: false, spaceID: "work")
        XCTAssertEqual(result.rows.count, 1); XCTAssertEqual(result.rows[0].title, "Work & home")
        XCTAssertEqual(result.rows[0].url, "https://example.com/?a=1&b=2")
    }
    func testChromiumJSONAndSizeLimit() throws {
        let json = #"{"roots":{"bookmark_bar":{"children":[{"name":"Example","url":"https://example.com"}]}}}"#
        XCTAssertEqual(try ImportParser.parse(Data(json.utf8), passwords: false, spaceID: "personal").rows.count, 1)
        XCTAssertThrowsError(try ImportParser.parse(Data(repeating: 65, count: ImportParser.limit + 1), passwords: true, spaceID: "work"))
    }
    func testDefaultSpacesHaveStableSeparateProfiles() {
        XCTAssertEqual(BrowserSpace.defaults.count, 4)
        XCTAssertEqual(Set(BrowserSpace.defaults.map(\.dataID)).count, 4)
        XCTAssertEqual(Set(BrowserSpace.defaults.map(\.id)).count, 4)
        XCTAssertEqual(BrowserSpace.defaults.map(\.id), ["personal", "work", "gaming", "shopping"])
        XCTAssertEqual(BrowserSpace.defaults[1].hex, "8a83ff")
        XCTAssertEqual(BrowserSpace.defaults[2].hex, "ff5da8")
        XCTAssertEqual(BrowserSpace.defaults[3].hex, "61d7ac")
    }
}
