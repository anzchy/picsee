/// Waits until `condition` holds, sleeping 5 ms between looks so a busy main actor still runs the work being waited
/// for. There is no wall-clock deadline: a loaded CI runner can queue the main actor for most of a minute (#277), so
/// the calling test's time limit bounds the wait instead, and cancellation by that limit ends it.
func waitUntil(isolation: isolated (any Actor)? = #isolation, _ condition: () async throws -> Bool) async rethrows {
    while !Task.isCancelled, try await !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}
