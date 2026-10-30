# Coverage Audit — PASS

Independent spec_attack agent followed official 0.10.2 coverage-auditor on fresh evidence: `.build/i231-fix2-unit.log` 1287 tests/36 suites passed, `.build/i231-fix2-lcov.log` export succeeded. No redundant heavy rerun. Contributor unit; merge single exact LCOV, 141 files.

| Metric | Covered/total | Threshold | Result |
|---|---|---|---|
| Lines | 14164/14164 (100%) |100%|PASS|
| Functions |2736/2736 (100%)|100%|PASS|
| Branches |unmeasured|0%|no enforced threshold|
| Statements |14164/14164 plugin line proxy|100%|PASS as proxy|

Independent statement coverage is unmeasured: official parser mirrors LCOV lines. Critical paths NOT CONFIGURED; mutation disabled.

Changed package files: RecentFolder.swift 4/4 lines,1/1 functions; AccessRebind.swift131/131 lines,23/23 functions; combined135/135 lines,24/24 functions. No measured gaps; no #284 exception needed. LLVM emits16 zero-hit generated closure FNDA rows outside its FNF/FNH denominator in unchanged ViewerChromeOverlay, DesignComponents and InspectorPanel; neither changed file has these rows. Totals follow LLVM summaries and official parser.

Four added package tests and three App tests carry behavioral assertions for persisted URLs/provenance, identities, compatibility round-trips, exact Undo bytes and controller recovery. No wiring-only changed test. No unreliable v8 ignore directives in App/package source/non-test scripts. No missing-coverage tests proposed. App code is outside package instrumentation and has a separate lane.
