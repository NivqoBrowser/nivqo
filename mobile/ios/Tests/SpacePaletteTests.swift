import XCTest
@testable import NIVQOProtocol

final class SpacePaletteTests: XCTestCase {
    func testUniqueSpaceColoursAndRenameRules() {
        let spaces = BrowserSpace.defaults
        XCTAssertTrue(SpacePalette.isAvailable("ffcf53", in: spaces))
        XCTAssertFalse(SpacePalette.isAvailable("8a83ff", in: spaces))
        XCTAssertTrue(SpacePalette.isAvailable("8a83ff", in: spaces, excluding: "work"))
        XCTAssertEqual(SpacePalette.nextAvailable(in: spaces), "ffa36d")
        XCTAssertTrue(SpacePalette.validName("  Travel  ", in: spaces))
        XCTAssertFalse(SpacePalette.validName(" work ", in: spaces))
        XCTAssertTrue(SpacePalette.validName("Work", in: spaces, excluding: "work"))
        XCTAssertFalse(SpacePalette.validName("   ", in: spaces))
        XCTAssertFalse(SpacePalette.validName(String(repeating: "x", count: 33), in: spaces))
    }
}
