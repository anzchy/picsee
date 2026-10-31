import Foundation
import Testing

/// #277: the macOS CI runner can queue the main actor for most of a minute, and Swift Testing counts that queue time
/// against `.timeLimit`, so a one-minute limit fails on CI for work that takes milliseconds locally (#331's four async
/// tests did, on PR #340). Every package test limit leaves room for that queueing: two minutes or more.
@Test func i331CIPackageTestTimeLimitsAllowForMainActorQueueing() throws {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let files = try #require(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    #expect(files.count > 50, "scanned \(tests.path)")
    var limits = 0
    for file in files {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in source.matches(of: /\.timeLimit\(\.minutes\((\d+)\)\)/) {
            limits += 1
            #expect(Int(match.1)! >= 2, "\(file.lastPathComponent): \(match.0) is shorter than CI's main-actor queueing")
        }
    }
    #expect(limits > 100, "found \(limits) time limits")
}
