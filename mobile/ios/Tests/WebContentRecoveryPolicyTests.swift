import XCTest
@testable import NIVQOProtocol

final class WebContentRecoveryPolicyTests: XCTestCase {
    private let page = URL(string: "https://example.com/article")!

    func testBlankHomeAndLocalURLsNeverReloadOrConsumeBudget() {
        var policy = WebContentRecoveryPolicy()
        for url in [nil, URL(string: "about:blank"), URL(string: "file:///tmp/page.html"), URL(string: "data:text/html,test")] {
            for _ in 0..<5 {
                XCTAssertEqual(policy.processTerminated(url: url, isSelected: true, isForeground: true), .ignore)
            }
        }
        XCTAssertEqual(policy.automaticReloadCount, 0)
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .reload)
    }

    func testDuplicateFailureCallbacksCoalesceBeforeReloadAndAfterExhaustion() {
        var policy = WebContentRecoveryPolicy()
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .reload)
        for _ in 0..<5 {
            XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .ignore)
        }
        XCTAssertTrue(policy.beginAutomaticReload())
        XCTAssertFalse(policy.beginAutomaticReload())
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .showRetry)
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .ignore)
        XCTAssertEqual(policy.automaticReloadCount, 1)
    }

    func testDidFinishCannotCreateInfiniteCrashReloadLoop() {
        var policy = WebContentRecoveryPolicy()
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .reload)
        XCTAssertTrue(policy.beginAutomaticReload())
        for _ in 0..<20 {
            policy.navigationFinished()
            XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .showRetry)
            XCTAssertFalse(policy.beginAutomaticReload())
        }
        XCTAssertEqual(policy.automaticReloadCount, 1)
    }

    func testBackgroundOrUnselectedTabsRequireUserRetry() {
        for (selected, foreground) in [(false, true), (true, false), (false, false)] {
            var policy = WebContentRecoveryPolicy()
            XCTAssertEqual(policy.processTerminated(url: page, isSelected: selected, isForeground: foreground), .showRetry)
            XCTAssertEqual(policy.automaticReloadCount, 0)
            XCTAssertFalse(policy.beginAutomaticReload())
            // Merely bringing the tab back does not begin an unsolicited reload.
            XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .ignore)
        }
    }

    func testClosingAndCancellingPreventQueuedReload() {
        var closed = WebContentRecoveryPolicy()
        XCTAssertEqual(closed.processTerminated(url: page, isSelected: true, isForeground: true, isClosed: true), .ignore)
        XCTAssertFalse(closed.beginAutomaticReload())
        var policy = WebContentRecoveryPolicy()
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .reload)
        policy.cancelScheduledReload()
        XCTAssertFalse(policy.beginAutomaticReload())
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .ignore)
    }

    func testOnlyExplicitNavigationOrRetryRenewsBudget() {
        var policy = WebContentRecoveryPolicy()
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .reload)
        XCTAssertTrue(policy.beginAutomaticReload())
        policy.automaticReloadFailed()
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .ignore)
        policy.userInitiatedNavigation()
        XCTAssertEqual(policy.automaticReloadCount, 0)
        XCTAssertEqual(policy.processTerminated(url: page, isSelected: true, isForeground: true), .reload)
    }
}
