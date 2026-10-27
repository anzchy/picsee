# Coverage Audit — PASS

Timestamp: 2026-10-27T07:55:36Z
Lane: `unit` (`swift test --package-path Packages/PicseeKit --enable-code-coverage`), 847 tests in 20 suites passed. `sh scripts/tdd/swift-lcov.sh` produced `coverage/lcov.info`.
Merge: single LCOV lane.

| Metric | Covered | Total | Threshold | Result |
| --- | ---: | ---: | ---: | --- |
| Lines | 8928 | 8928 | 100% | PASS |
| Functions | 1802 | 1802 | 100% | PASS |
| Branches | n/a | n/a | 0% | NOT MEASURED |
| Statements | n/a | n/a | 100% | NOT MEASURED |

No uncovered lines or functions. The known `FileItemIdentityResolver.swift:65–67` export gap did not appear in the final run. No coverage-ignore directives were added. The App menu-event test bundle is separate from package LCOV and passed 8 tests.
