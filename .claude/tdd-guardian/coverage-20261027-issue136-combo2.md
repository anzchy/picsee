# Coverage Audit — PASS

Timestamp: 2026-10-27T06:28:59Z
Lane: `unit` (`swift test --package-path Packages/PicseeKit --enable-code-coverage`), 802 tests in 20 suites passed. `sh scripts/tdd/swift-lcov.sh` produced `coverage/lcov.info`.
Merge: single LCOV lane.

| Metric | Covered | Total | Threshold | Result |
| --- | ---: | ---: | ---: | --- |
| Lines | 8649 | 8649 | 100% | PASS |
| Functions | 1730 | 1730 | 100% | PASS |
| Branches | n/a | n/a | 0% | NOT MEASURED |
| Statements | n/a | n/a | 100% | NOT MEASURED |

No uncovered lines or functions. The known `FileItemIdentityResolver.swift:65–67` flaky gap appeared in the first full run, then was covered in the final rerun. No new coverage-ignore directives. App window tests run as a separate bundle outside package LCOV.
