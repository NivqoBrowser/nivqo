import Foundation

/// A tab gets at most one automatic reload between explicit user navigations.
/// Finishing a load deliberately does not replenish that budget: a page can
/// finish loading and then repeatedly crash its WebKit content process.
struct WebContentRecoveryPolicy {
    enum Action: Equatable { case ignore, reload, showRetry }
    private enum State: Equatable { case ready, scheduled, attempted, retryRequired }
    private var state = State.ready
    private(set) var automaticReloadCount = 0

    mutating func userInitiatedNavigation() {
        state = .ready
        automaticReloadCount = 0
    }

    mutating func processTerminated(url: URL?, isSelected: Bool, isForeground: Bool, isClosed: Bool = false) -> Action {
        // Home/blank and local documents have nothing suitable to reload.
        guard !isClosed, let url = url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return .ignore }
        switch state {
        case .scheduled, .retryRequired:
            // didFail and process-termination delegates can describe one event.
            return .ignore
        case .attempted:
            state = .retryRequired
            return .showRetry
        case .ready:
            guard isSelected && isForeground else {
                state = .retryRequired
                return .showRetry
            }
            state = .scheduled
            automaticReloadCount += 1
            return .reload
        }
    }

    mutating func beginAutomaticReload() -> Bool {
        guard state == .scheduled else { return false }
        state = .attempted
        return true
    }

    mutating func cancelScheduledReload() {
        if state == .scheduled { state = .retryRequired }
    }

    mutating func automaticReloadFailed() { state = .retryRequired }

    mutating func navigationFinished() {
        // A successful load may dismiss a stale notice, but retains its budget.
        if state == .retryRequired { state = .attempted }
    }
}
