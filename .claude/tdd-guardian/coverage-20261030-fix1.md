# Coverage Audit — PASS with explicit #284 baseline exception

Independent coverage_review agent inspected final exact single LCOV (141 production files) and fresh contributor evidence: .build/i231-fix1-wi2-unit.log 1278 tests/36 suites PASS; .build/i231-fix1-wi2-lcov.log export PASS. Source/test modifications precede run/export. No redundant rerun of unchanged passing lane.

| Scope | Lines | Functions |
|---|---|---|
| Changed package files |1190/1190|176/176|
| AccessRebind.swift |124/124|21/21|
| FileAccess.swift |1066/1066|155/155|
| Package excluding explicit unchanged #284 exception |13776/13776|2671/2671|
| Raw package |14145/14176|2728/2740|

Only gaps: unchanged ShortcutCatalog157/182L19/27F and ShortcutListView212/218L38/42F. Raw absolute thresholds would fail without the user's explicit exception. No changed-file gaps, threshold/config edits, approximate merge or coverage-ignore directives.

Branches/statements unmeasured, not100%; criticalPaths not configured; mutation disabled. App outside package coverage has separate150-test gate. Five added/modified test declarations carry Level1–5 behavioral checks: real persisted mappings/IDs, exact failure/Undo snapshots, controller state and enabled controls/successful retries. Log/reporter counts are supplemental. S5 transitions/roundtrips covered; no wiring-only changed case. No further tests proposed. No files edited by auditor; parent persisted this report.
