import XCTest
@testable import NIVQOProtocol

final class SearchHistoryTests: XCTestCase {
    func testRecentSearchesShowWithoutTypingAndFilterWithinSpace() {
        var list: [SearchHistoryItem] = []
        list = SearchHistory.recording("best phones 2026", spaceID: "personal", in: list)
        list = SearchHistory.recording("pasta recipes", spaceID: "personal", in: list)
        list = SearchHistory.recording("phone cases", spaceID: "work", in: list)
        XCTAssertEqual(SearchHistory.matching("", spaceID: "personal", in: list).map(\.query), ["pasta recipes", "best phones 2026"])
        XCTAssertEqual(SearchHistory.matching("PHONE", spaceID: "personal", in: list).map(\.query), ["best phones 2026"])
        XCTAssertEqual(SearchHistory.matching("phones", spaceID: "work", in: list).count, 0)
    }
    func testDeduplicatesCaseInsensitivelyAndPreservesOtherSpaces() {
        let first = SearchHistory.recording("  Best    Phones  ", spaceID: "personal", in: [])
        let second = SearchHistory.recording("best phones", spaceID: "work", in: first)
        let third = SearchHistory.recording("BEST phones", spaceID: "personal", in: second)
        XCTAssertEqual(third.count, 2)
        XCTAssertEqual(third[0].query, "BEST phones")
        XCTAssertEqual(third[1].spaceID, "work")
    }
    func testMatchesPrefixBeforeContainsAndRespectsLimit() {
        var entries: [SearchHistoryItem] = []
        for query in ["new shoes", "shoes shopping", "shoe repair", "shoe guides"] {
            entries = SearchHistory.recording(query, spaceID: "personal", in: entries)
        }
        XCTAssertEqual(SearchHistory.matching("shoe", spaceID: "personal", in: entries, limit: 2).map(\.query), ["shoe guides", "shoe repair"])
    }
}
