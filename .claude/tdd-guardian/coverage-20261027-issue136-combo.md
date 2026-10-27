# Coverage Audit — PASS

Lane: `unit` (`swift test --package-path Packages/PicseeKit --enable-code-coverage`), 772 tests in 20 suites passed. `sh scripts/tdd/swift-lcov.sh` produced `coverage/lcov.info`.

| Metric | Covered | Total | Threshold | Result |
| --- | ---: | ---: | ---: | --- |
| Lines | 8536 | 8536 | 100% | PASS |
| Functions | 1702 | 1702 | 100% | PASS |
| Branches | n/a | n/a | 0% | NOT MEASURED |
| Statements | n/a | n/a | 100% | NOT MEASURED |

Merge method: single LCOV lane. The App target is outside package LCOV; its five compiled bundle tests passed separately with `xcrun xctest`.
