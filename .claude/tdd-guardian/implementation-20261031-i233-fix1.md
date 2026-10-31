# WI-5 — #233 replacement File Grant probe regression

## Result

The requested M1 schedule is already rejected by the existing implementation. `AccessOperation.isCurrent` in `Packages/PicseeKit/Sources/PicseeApplication/Access/AccessIntent.swift:17` checks both token equality and `!Task.isCancelled`. Replacing a probe synchronously cancels the previous Task before installing the next one. Consequently the existing operation/input checks reject its result even when the delivered error is an earlier non-cancellation error and all three generations are unchanged.

No production fix or new probe token is needed. The original #233 brief explicitly permits controlled-revert evidence for criteria already held on main. The final change adds one native parameterized integration regression with four schedules in `AppTests/Issue233ReplacementProbeTests.swift`; it preserves the existing production controller byte for byte. ACCESS-03 acceptance, limitations, status and generated HTML are unchanged.

## Test and observable assertions

`issue233ReplacedProbeHeldCompletionsNeverDeliver` covers `failedReadRelease`, `successfulReadRelease`, `bookmarkSuccess` and `bookmarkFailure`. The actual native controller/session/ImageIO pipeline and concrete FileAccess actor execute. A real FileHandle open/read is used; the failed-read case proves a real non-cancellation POSIX permission failure while the release is held. A one-shot system-boundary identity/bookmark fixture resolves P1's File Grant request to real alternate B, whose final lease release is independent of the source lease retained for displayed A. The original File Grant URL remains A throughout P1/P2; no input/access/loader generation change is used to explain rejection.

The test holds a synchronous SecurityScope.stop or BookmarkCoding.resolve boundary on FileAccess's executor using a condition, never MainActor. P2 starts synchronously before MainActor signals the gate; both tasks are awaited afterwards. It asserts P1 was cancelled, P2 remains current, a real P2 acquisition occurs, no sheet notification or attached sheet appears, and image/key/phase/generation/URL/title/proxy/Inspector remain unchanged. An unchanged actual pipeline header-request count additionally detects stale successful-probe reconciliation even when an unchanged image would render identically. The success controlled revert below proves that count oracle discriminates.

The temporary diagnostic trace `.build/i233-fix1-gate-trace.log` proves both release gates were inside `FileAccess.release` (lines 20/50) and both bookmark gates inside `resolveFileGrant` (lines 81/112). Diagnostics were removed before the valid controlled RED. No fixture interface was added to production code, no parent folder enumeration was added, and root storage stays absent.

## Already-existing post-await delivery guards

All are in `reportFileGrantReadFailure` in `App/CanvasWindowController.swift`:

1. AccessServices Task completion: `operation.isCurrent` rejects a retired Task before starting the lease/read.
2. Successful `withLease` completion, including awaited release: operation/input current plus grant URL and loader generation checks precede reconcile delivery.
3. Throwing `withLease` completion, including awaited release: the same checks precede error mapping, quiet clear or reconnect.
4. Successful bookmark re-resolution: the same checks precede following the resolved file/reconcile.
5. Throwing bookmark re-resolution: the same checks precede replacing the failure and the eventual clear/reconnect boundary.

There is no intervening suspension between the last applicable guard and its synchronous presentation mutation. The cancellation component is supplied centrally by AccessOperation.isCurrent; the error-type CancellationError checks are supplementary and are not the only cancellation check.

## RED/GREEN and separation

Receipt: `P2-08c-T6-WI-5`, app-red lane, identical `PICSEE_SWIFT_FILTER=issue233ReplacedProbeHeldCompletionsNeverDeliver` on record and verify.

The unmodified baseline first passed all four schedules. This is explicitly **not an implementation-before/after RED**. For independent regression discrimination, temporarily omit operation/input current checks at only the five probe post-await guards above; retain grant/generation checks and all other controller code. Save the exact source before this controlled mutation, record genuine assertion RED, and restore its exact bytes before GREEN verify.

- Source before/after restoration SHA256: `d001e56edf5b8e8a4f35d8e0e21fe589ea23a596950c4dcdbf9a923d764111b1`.
- Temporary controlled-mutant SHA256: `49a3752825a2439d3a83bd2b63f24b836f2f8ab005a291a20136500ef4149935`.
- RED `.build/i233-fix1-controlled-record.log`: `Red recorded for P2-08c-T6-WI-5 (assertion-failure): 1 of 1 tests failed.`
- Raw RED `.build/i233-fix1-controlled-red-app.log`: failedReadRelease line 204 `(sheets → 1) == 0`, line 206 `hasImage → false`; successfulReadRelease line 215 `(pipeline.headerCount → 3) == (headers → 2)`; bookmarkSuccess and bookmarkFailure each report `(sheets → 1) == 0` and cleared presentation. Line numbers are those at RED, before the later additive assertion.
- Exact original CVC restored using its saved copy; `cmp` passed before verify.
- GREEN `.build/i233-fix1-green-app.log`: `Test issue233ReplacedProbeHeldCompletionsNeverDeliver(_:) with 4 test cases passed after 1.598 seconds.` and `Test run with 1 test in 0 suites passed after 1.598 seconds.`
- Verify `.build/i233-fix1-verify.log`: `Specification held for P2-08c-T6-WI-5 — no recorded line changed between red and green.` The expected MEDIUM implementation-already-present note describes the deliberate controlled omission at RED, not an undisclosed implementation.
- After verify, one supplementary assertion was **added** immediately after awaiting P2 and before the explicit actor-drain call, so the identity visit count cannot be satisfied by the drain itself. Every recorded line is intact. The parent runs the final selected App gate against this addition; the earlier GREEN is not represented as having run that later assertion.

## Pre-valid-RED setup history

Preserved invalid attempts are disclosed; none is claimed as valid RED:

1. `.build/i233-fix1-record.log` / runner-diagnosis: generated Xcode project predated the new test file, so selection discovered zero tests. Run wrapped xcodegen generate to include it.
2. `.build/i233-fix1-record-retry.log`: a setup assumption incorrectly waited for active scopes to be zero, while the displayed source correctly retains A's lease. The diagnostic runner was sampled and terminated; no reliable completed assertion result is claimed. Correct the fixture to hold an independent B lease and remove the invalid setup assumption, before changing production.
3. `.build/i233-fix1-record-red.log` and `.build/i233-fix1-record-diagnose.log`: baseline GREEN, which is correct because cancellation-aware isCurrent already guards the deliveries. The diagnostic trace verified actual held boundary locations. No production changes existed in those baseline runs.

`.build/i233-fix1-precontrolled-receipts.json` preserves the prior receipt state before the authorized controlled RED replaced the same work-item entry. No settled valid receipt was overwritten. No existing test assertion was weakened to obtain GREEN.

## Native selected runner and configuration

The checked-in app-lane runs the entire bundle and ignores PICSEE_SWIFT_FILTER. For this request's selected-only lane, a local ignored Swift runner dlopens the actual compiled App test bundle and calls public `Testing.__swiftPMEntryPoint(passing:)` with filter and serial execution. Files: `.build/i233-fix1-app-runner.swift`, its compiled runner, and `.build/i233-fix1-app-lane.mjs`. The wrapper rejects zero/incomplete summaries and prints the normal Tests run/Failures line. It persists raw output to `.build/i233-fix1-app-last.log`; immutable RED/GREEN copies are named above. Initial tooling probes confirmed xctest -XCTest selects zero Swift Testing tests and xctest --filter is unsupported; these were not RED evidence.

Only the local app-red command was temporarily changed to `node .build/i233-fix1-app-lane.mjs`; its setup remained build-for-testing. `.claude/tdd-guardian/config.json` was restored byte-identical to `.build/i233-fix1-original-config.json` after verify, before final package validation. No tracked runner, project.yml, entitlement, package API or production source is changed.

All heavy jobs run serially in the foreground as `/Users/jack/.picsee/device/ram/with-ram.sh i233 scripts/heavy-lock.sh COMMAND`, including receipt record/verify and their nested setup. Waiting on the shared lock is preserved in logs; no duplicate build/test job was launched to bypass another task.

## Implementer validation

- Package coverage lane `.build/i233-fix1-package.log`: `Test run with 1294 tests in 36 suites passed after 53.094 seconds.`
- Coverage export `.build/i233-fix1-lcov.log`: `swift-lcov: wrote coverage/lcov.info`.
- xcodegen `.build/i233-fix1-xcodegen.log` passed with final new test file included.
- Final unsigned build, selected App gate for the additive assertion, independent coverage audit, review and commit gate refresh are owned by the parent. Do not infer their results from this report.

Critical paths: NOT CONFIGURED. Mutation: disabled. Push-trigger lanes: NOT CONFIGURED. Package instrumentation does not measure native controller lines. Signed-device acceptance, actual system powerbox acceptance, true TCC revocation and physical sleep/wake remain unverified; no status upgrade is claimed.
