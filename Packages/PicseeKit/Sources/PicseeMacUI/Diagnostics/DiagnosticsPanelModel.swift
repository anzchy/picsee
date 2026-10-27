import Foundation
import Observation
import PicseeCore

/// One figure. `title` is a localization key; `value` is a count, a byte size or `DiagnosticsPanelModel.unknown`.
public struct DiagnosticsRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let value: String
}
public struct DiagnosticsSection: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let rows: [DiagnosticsRow]
}

/// The diagnostics panel's rows (CACHE-04). While visible it reads the source now and then once per interval;
/// hiding cancels the loop, and a read that was in flight is dropped. Values are counts and sizes only.
@MainActor @Observable
public final class DiagnosticsPanelModel {
    /// Localization key shown for any figure the source could not provide.
    public static let unknown = "Unknown"
    public private(set) var sections: [DiagnosticsSection] = DiagnosticsPanelModel.sections(nil)
    public private(set) var isVisible = false
    private let source: any DiagnosticsProviding
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var loop: Task<Void, Never>?

    public init(source: any DiagnosticsProviding, interval: Duration = .seconds(1),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.source = source; self.interval = interval; self.sleep = sleep
    }

    public func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        loop?.cancel()
        loop = nil
        guard visible else { return }
        loop = Task { [weak self, source, interval, sleep] in
            while !Task.isCancelled {
                let snapshot = await source.diagnostics()
                guard !Task.isCancelled, let self else { return }
                self.sections = Self.sections(snapshot)
                do { try await sleep(interval) } catch { return }
            }
        }
    }

    static func sections(_ snapshot: DiagnosticsSnapshot?) -> [DiagnosticsSection] {
        let count = { (value: Int?) in value.map(String.init) ?? unknown }
        let memory = { (value: Int?) in value.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? unknown }
        let file = { (value: Int64?) in value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? unknown }
        let budget = snapshot?.budget, cache = snapshot?.memoryCache, disk = snapshot?.diskCache, decoding = snapshot?.decoding
        func section(_ id: String, _ title: String, _ rows: [(String, String, String)]) -> DiagnosticsSection {
            DiagnosticsSection(id: id, title: title,
                               rows: rows.map { DiagnosticsRow(id: "\(id).\($0.0)", title: $0.1, value: $0.2) })
        }
        return [
            section("budget", "Memory Budget", [
                ("limit", "Limit", memory(budget?.limit)), ("pinned", "Pinned", memory(budget?.pinned)),
                ("evictable", "Evictable", memory(budget?.evictable)), ("staging", "Decode Staging", memory(budget?.staging)),
                ("peak", "Peak", memory(budget?.peak))]),
            section("memory", "Memory Cache", [
                ("entries", "Entries", count(cache?.entries)), ("size", "Size", memory(cache?.bytes)),
                ("hits", "Hits", count(cache?.hits)), ("misses", "Misses", count(cache?.misses))]),
            section("disk", "Thumbnail Disk Cache", [
                ("entries", "Entries", count(disk?.entries)), ("size", "Stored Size", file(disk?.storedBytes)),
                ("hits", "Hits", count(disk?.hits)), ("misses", "Misses", count(disk?.misses))]),
            section("decoding", "Decoding", [
                ("running", "Running", count(decoding?.running)), ("waiting", "Waiting", count(decoding?.waiting)),
                ("finished", "Finished Decodes", count(decoding?.finished))]),
        ]
    }
}
