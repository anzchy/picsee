# Real Swift output fixtures

Captured on 2026-10-22 with Swift 6.3.3 (Xcode 26.6, 17F113), using a scratch SwiftPM package. These are unedited merged stdout/stderr, not invented runner output. Absolute paths and timestamps are evidence of that run.

To reproduce, create a scratch directory outside the repo containing `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LaneFixtures", targets: [.testTarget(name: "LaneTests")])
```

Create `Tests/LaneTests/`, then run from the worktree root:

```sh
scripts/heavy-lock.sh python3 scripts/tdd/fixtures/capture.py /absolute/path/to/scratch
```

The generator writes each exact test source alongside scratch, runs `swift test --package-path <scratch>` for each source, and writes `fixture-capture.txt` with commands, exit codes and full output in scratch's parent. It refreshes the five tracked output fixtures here.

| Fixture | Exit | Expected completed results |
|---|---|---|
| swift-pass | 0 | 3 total, 2 passed, 0 failed, 1 disabled |
| swift-fail | 1 | 3 total, 1 passed, 1 failed with **two issues**, 1 disabled |
| compile-fail | 1 | undefined symbol, no completed run |
| xctest-pass | 0 | 12 total, 11 passed, 0 failed, 1 skipped |
| xctest-fail | 1 | 12 total, 10 passed, 1 failed, 1 skipped |

Swift Testing fixtures include XCTest's empty companion summary; XCTest fixtures include Swift Testing's empty companion summary and three repeated XCTest suite summaries. The adapter adds the two frameworks' distinct totals but counts XCTest's repeated rollups once. XCTest failure output contains both the `error: -[... ] : XCTAssertEqual failed` diagnostic and the failed case result.

Run `node --test scripts/tdd/*.test.mjs`. Tests use the newest installed tdd-guardian under `~/.claude/plugins/cache/xiaolai/tdd-guardian/`, or `PICSEE_TDD_PLUGIN_ROOT`, to check actual plugin classification. They replace only the external `swift` executable with a fixture playback process; the real wrapper and lock still execute. Temporary tests live in the ignored `.build/tdd-tests/`.
