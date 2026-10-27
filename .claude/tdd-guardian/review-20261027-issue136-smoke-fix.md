# TDD Review — APPROVED WITH NOTES

Timestamp: 2026-10-27T07:56:00Z
Scope: #136 smoke fix D1/D2, App and package tests, TDD lane, ledger.

| Severity | Count |
| --- | ---: |
| High | 0 |
| Medium | 0 |
| Low | 1 |

## Behavior and test quality

- D1 dispatches a real ⌘I NSEvent through the installed `NSApp.mainMenu`; the assertion checks both toggles, field visibility, first responder, query, caret, and subsequent insertion. The initial assertion failed on the original menu action, and an added visibility assertion caught a later end-editing collapse. Both RED cases were observed before their corresponding fixes. The test uses a controller-provider seam because a headless `xctest` process cannot acquire `NSApp.keyWindow`.
- D1 keeps ordinary Tab-driven search collapse. The package test exercises the one pending end-editing callback and the expiration of that suppression.
- D2 checks actual laid-out label ink/row height in an `NSWindow` at 195 and 220 pt for English and zh-Hans; a rendered wrapping probe checks the 7 pt value gap. Full-panel parity references the new shared localized label width.
- No internal module was mocked. Assertions about menu handling, focus, text, rendered geometry and pixels are behavioral (L3–L4, S5). The Node config assertion checks the required heavy-lock wiring for the new manual RED lane.

## Note

- A signed-App re-smoke is still required. The headless test proves the menu equivalent path but supplies the target window through an injectable controller provider because its `NSApplication` cannot become key.

Receipts `issue136-SMOKE-WI-1` and `-WI-2`: `SEPARATION-HELD`. Package coverage: 8928/8928 lines, 1802/1802 functions. Mutation disabled by repository config.
