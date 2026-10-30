# WI-1: #231 recorded Recent location (P2-08c / ACCESS-03)

## Tests written
- `AccessRebindTransactionTests.swift`: four new declarations. Real-bookmark promotion has fresh/merge × misleading-folder absent/present cases, second rebind and exact Undo bytes/memory; inverse newer epoch and legacy fallback; literal old JSON/additive round-trip; mismatched provenance and escaping destination.
- `LostAccessRecoveryTests.swift`: production rememberFolder through overlapping inactive root moves and committed remap, service grant/reconnect/unmatched reselect provenance, plus additive matching reselect coverage. Nested-root fixture parameter has unchanged default.
- JSON field injection allows genuine pre-fix compilation without production stubs.

## Implementation
- `RecentFolder.swift`: optional `recordedRoot: URL?`, initializer defaults nil, synthesized Codable decodes old records without the field.
- `AccessRebind.swift`: present provenance is the sole suffix source; missing provenance retains round-1 latest/history fallback; present provenance advances to destination for later rebinds. Destination containment and collision/missing-only rules stay in place.
- `AccessServices.swift`: grant/reconnect/reselect recording stores selected/current root location.
- `CanvasWindowController.swift`: rememberFolder records the actual Access Root URL, not its browsed child.

## RED evidence
- `P2-08c-T4-Fix2-WI-1`, swift-red filter `t231Fix2`: genuine 4/4 failed; `.build/i231-fix2-swift-red.log`.
- `P2-08c-T4-Fix2-WI-1-App`, app-red after successful unsigned build: genuine 3/152 failed; `.build/i231-fix2-app-red.log`.
- Raw pre-fix detail rerun: 2/152 failed, only intended new production-recording/rebind and service-recording cases, 7 issues; `.build/i231-fix2-app-red-detail.log`. It shows actual wrong `Replacement/album/One` versus expected `Replacement/One`, plus absent provenance. The extra original receipt failure is unidentified; original receipt was preserved and never overwritten.
- Both receipt dirty-source notes list only parent limitation edits in `docs/feature-ledger.md`. No production source was changed at RED.
- Matching reselect test was appended after App RED, before implementation; no recorded lines/assertions were edited.

## Verification and environment evidence
- First Swift verification PENDING runner-error (`.build/i231-fix2-swift-verify.log`). Direct diagnostic isolated stale SwiftPM test object references to the old RecentFolder initializer ABI (`.build/i231-fix2-swift-green-detail.log`), before any test could complete.
- Wrapped `swift package --package-path Packages/PicseeKit clean` repaired cache only; no source/test changes for that linker error. Original receipt then green, Specification held (`.build/i231-fix2-swift-verify-clean.log`).
- App green unsigned build succeeded (`.build/i231-fix2-app-green-build.log`).
- App original receipt verification green, Specification held, no recorded line changed (`.build/i231-fix2-app-verify.log`).

## Status: DONE (targeted implementation)
Both original receipts held. Full final gates remain parent-owned as assigned.

## Scope and remaining gates
No commits/push/PR. Parent owns full package coverage/LCOV, final App raw lane/integration/build gates, ledger generation, independent audits, commit and handoff. M1 and M3 remain open; M2 behavior untouched. Signed sandbox/TCC/device behavior remains unverified.

## Final App synchronization correction
Parent final raw run `.build/i231-fix2-app-final.log` found the new overlap test reading the unchanged original `container/album/One` plus an unrelated existing sidebar ABA timeout. The new test had treated the fixture's next paused mount query as proof that rebind had committed. That query can belong to a foreground recheck still running after rootURL publication or openRecent recovery. Rebind's actual synchronous transaction precedes root publication and later reconciliation/reauthorization. Added a wait for source-root retirement and the new destination record before reading Recent bytes. This adds synchronization only: every recorded assertion/line is unchanged, no production change, and no sidebar change. Original failing log and original receipts remain intact. Follow-up build/raw runs/receipt verify pending below.

Also armed the existing real filesystem read gate for the replacement scan before selection, with explicit/deferred release after the unchanged mapped assertions. This prevents normal scan completion from remembering the replacement root before inspection if a different foreground query consumed the mount pause. Both guards add lines only; recorded assertions remain intact.

### Synchronization follow-up results
- `.build/i231-fix2-app-sync-build.log`: unsigned build succeeded with both added guards.
- `.build/i231-fix2-app-sync-run1.log`: new fix2 overlap and service/matching-reselect tests passed. Full App failed 1/153 in unchanged round-1 `t231Fix1ForegroundFollowsInactiveRootThenRebindRemapsHistoricalRecent`: `.unknown` instead of `.notFound` before selection, then five downstream rebind/strip expectations failed. This is a different failure from the corrected fix2 precommit-inspection race. Sidebar passed this run.
- Stopped on that gate failure. Run2 and original App receipt re-verification of synchronization additions have not run yet. Original earlier held receipts and failed logs remain preserved. Parent notified; no edits to round-1 assertions or unrelated sidebar.

### Round-1 readiness diagnosis and correction
`requestFolderReconnection` synchronously calls `handleAccessLoss` and renders page 26, then launches a Task awaiting `monitor.register` and `reportReadFailure`. When the monitor is still readable, the synchronous page cause is `.unknown`; only the later real root verification publishes `.lost(.notFound)` and updates the controller. The old page/rootID wait therefore did not prove final cause classification, and its subsequent selection sometimes entered reselect rather than rebind. Added an explicit final-notFound wait to both historical App regressions, preserving their existing assertions. Added the same real replacement-read gate and postcommit root-record wait to round1, which had the identical mount-only commit barrier. These are deterministic test-readiness fixes only; production behavior, existing assertions, and recorded lines remain unchanged. Follow-up build/two full raw App runs/original App receipt verify requested by parent.

### Final frozen App verification
- `.build/i231-fix2-app-ready-build.log`: unsigned build PASS after final readiness additions.
- `.build/i231-fix2-app-ready-run1.log`: full App 153/153 PASS, zero failures/errors/skips.
- `.build/i231-fix2-app-ready-run2.log`: second consecutive full App 153/153 PASS, zero failures/errors/skips.
- `.build/i231-fix2-app-ready-verify.log`: original receipt CLI exit0, but explicitly no new judgement because receipts had settled on the earlier green run. This is not reported as a fresh lane execution.
- `.build/i231-fix2-current-spec.log`: read-only official `verification.verifyReceipt` against original stored RED and current `fingerprintFiles` returns SEPARATION-HELD for both package and App. App notes spec-extended with every recorded line intact; only MEDIUM is the original pre-RED docs ledger edit. Original receipts were not reset or rewritten for this current fingerprint audit. The two raw full App passes supply current green evidence.

All original failures preserved: App RED receipt3/152 (extra unidentified failure), raw pre-fix detail2/152 intended failures, parent's first final raw2/153 (new fix2 precommit inspection + unrelated sidebar ABA), and sync-run1 raw1/153 (old round1 interim-unknown readiness). Final deterministic additions resolve only the demonstrated test barriers. No production changes after initial minimal fix, no changes to sidebar, no modified existing expectations. Source/tests are frozen; parent owns remaining integration/ledger/whitespace gates and final commit/handoff.
