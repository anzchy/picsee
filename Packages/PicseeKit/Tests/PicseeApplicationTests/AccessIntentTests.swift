import Foundation
import Testing
import PicseeApplication

/// A listing/store/old-source close that can return only when explicitly released.
private actor AccessSuspension {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var waiting = false
    func suspend() async {
        await withCheckedContinuation {
            continuation = $0; waiting = true
            entered?.resume(); entered = nil
        }
    }
    func waitUntilEntered() async {
        if !waiting { await withCheckedContinuation { entered = $0 } }
    }
    func resume() { continuation!.resume(); continuation = nil }
}

private enum AccessTestFailure: Error { case expected }

@Test @MainActor func accessIntentDiscardsSuspendedOpensAndErrorsAfterCloseNewOpenOrCancellation() async {
    // Listing, Recent write, grant containment/listing, and old-source close
    // are all suspensions after which App must consult the same operation.
    for stage in 0..<4 {
        for invalidation in 0..<3 {
            for fails in [false, true] {
                let intent = AccessIntent()
                let operation = intent.begin()
                let suspended = AccessSuspension()
                var presented: [String] = []
                let task = Task { @MainActor in
                    do {
                        for index in 0..<4 {
                            try await operation.wait {
                                if index == stage {
                                    await suspended.suspend()
                                    if fails { throw AccessTestFailure.expected }
                                }
                            }
                        }
                        presented.append("A")
                    } catch {
                        if operation.isCurrent { presented.append("stale error") }
                    }
                }
                await suspended.waitUntilEntered()
                switch invalidation {
                case 0: intent.invalidate() // window closed
                case 1: _ = intent.begin(); presented.append("B")
                default: task.cancel()
                }
                await suspended.resume()
                await task.value
                #expect(presented == (invalidation == 1 ? ["B"] : []))
            }
        }
    }
}

@Test @MainActor func accessIntentAllowsCurrentResultsAndErrorsButDoesNotStartExpiredWork() async throws {
    let intent = AccessIntent()
    let operation = intent.begin()
    #expect(operation.isCurrent)
    #expect(try await operation.wait { 42 } == 42)
    await #expect(throws: AccessTestFailure.expected) {
        try await operation.wait { throw AccessTestFailure.expected }
    }
    intent.invalidate()
    var started = false
    await #expect(throws: CancellationError.self) {
        try await operation.wait { started = true }
    }
    #expect(!started)
}

@Test @MainActor func accessFolderOpenDiscardsBlockedListingAndRecentWriteAfterCloseOrNewOpen() async {
    for blockListing in [true, false] {
        for newOpen in [true, false] {
            for fails in [true, false] {
                let intent = AccessIntent()
                let operation = intent.begin()
                let suspended = AccessSuspension()
                let task = Task { @MainActor in
                    try await operation.firstImage(list: {
                        if blockListing {
                            await suspended.suspend()
                            if fails { throw AccessTestFailure.expected }
                        }
                        return [URL(fileURLWithPath: "/photos/a.jpg")]
                    }, remember: {
                        if !blockListing {
                            await suspended.suspend()
                            if fails { throw AccessTestFailure.expected }
                        }
                    })
                }
                await suspended.waitUntilEntered()
                if newOpen { _ = intent.begin() } else { intent.invalidate() }
                await suspended.resume()
                await #expect(throws: CancellationError.self) { try await task.value }
            }
        }
    }
}

@Test @MainActor func accessFolderOpenReturnsFirstImageAndRemembersOnlyNonemptyFolders() async throws {
    let operation = AccessIntent().begin()
    var remembered = 0
    let first = try await operation.firstImage(list: {
        [URL(fileURLWithPath: "/photos/b.jpg"), URL(fileURLWithPath: "/photos/a.jpg")]
    }, remember: { remembered += 1 })
    #expect(first == URL(fileURLWithPath: "/photos/a.jpg"))
    let empty = try await operation.firstImage(list: { [] }, remember: { remembered += 1 })
    #expect(empty == nil && remembered == 1)
}
