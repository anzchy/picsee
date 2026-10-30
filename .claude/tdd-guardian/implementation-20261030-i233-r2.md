# WI-4: Approved File Grant next-access reader forwarding

## Status

Implementation is complete with all executable gates PASS and final review APPROVED (zero findings). WI-3 and WI-4 were committed separately as directed; the tracked report convention is retained. The implementer left the WI-3 index snapshot intact; root made the commits. No push, PR, device run or status upgrade was performed.

Authority: `/Users/jack/.picsee/herdr/gpt-imple-1/i233-amendment-approved.md`; new plan/matrix/adversary `*-20261030-i233-r2.md`, including approved additive reconciliation and rejected-input liveness cases. No Input, WindowInspectorReader, AppDelegate, folder-root handling, grid/footer/sidebar, ViewerStateHost, design, project.yml or entitlement change.

## Tests written

- New `AppTests/Issue233FileGrantReaderFailureTests.swift`: 6 native tests. Real temporary PNG + native scope + ImageIO; existing ImagePipeline and FileIdentityResourceReading decorators control timing without fabricating file failures.
  - Inspector-only POSIX denial with populated Inspector/pixels, ordinary reconcile held, full native clearing inside willBeginSheet.
  - Existing-file loader denial with ordinary reconcile held, full clearing, late held result excluded.
  - Stale metadata after settled B; A probe captured before newer input B; B held at actual identityRoot admission before access authority advances; late A metadata and old A reconcile released while B is still held. A generation/identity remains intact, no recovery UI; B subsequently settles.
  - Readable metadata failure and real readable-corrupt PNG data remain ordinary reader/decode errors. Successful access probe has stable pipeline counts, no automatic reopening/redecode loop.
  - After real rejected ZIP input leaves A active, release old pre-B metadata first (silent), then separately make a real fresh Inspector show/read or a real canvas actualPixels demand. Real chmod denial is found without foreground/wake/reconcile rescue. Inspector episode prewarms full detail so viewport changes cannot mask missing Inspector forwarding; loader episode hides Inspector to isolate loader forwarding.
  - Real move after the FileAccess identity boundary returns the old identity, yielding stale lease -> actual open failure. Same-volume rename and ordinary `.Trash` follow; system Trash clears quietly. No reconnect or parent/root scope request; original and moved native identities/representedURL/title checked.
- New `Packages/PicseeKit/Tests/PicseeApplicationTests/Issue233InspectorFailureCallbackTests.swift`: 5 tests for optional/current mapped-state callback + success, clear/replacement exclusion with completed-reader evidence, cancellation without generation change, reentrant synchronous clear, and per-read callback snapshot when configuration changes while I/O is pending.

## Implementation

`InspectorMetadata.swift` adds only an optional `@ObservationIgnored` MainActor failure callback. Each actual read snapshots its configured callback before its Task starts. Failure delivery remains AFTER existing generation/cancellation guards and AFTER mapped state assignment. This permits synchronous clearing without a later old catch overwriting it.

Owned `CanvasWindowController.swift` File Grant hunks:

- Bind read-origin input at actual Inspector show/explicit refresh; passive window updates retain their origin. Old pending callbacks cannot acquire a newer input stamp. Folder-root callbacks are ignored by this binding and retain their existing reporting path.
- Actual new canvas detail demand renews the loader stamp only for settled -> refining; it does not retag an already in-flight read.
- Generic File Grant loader failure forwards to a natural, lifecycle-owned Task. Caller/test can await actual completion without injecting a fake production seam. Probe captures access/input/loader generation before asynchronous I/O; stale input does not cancel newer admission.
- Probe uses ONLY a File Grant lease and actual one-byte FileHandle open/read. A successful readable same-file probe performs no ImageIO, reopen or retry. A changed resolved URL goes through existing bookmark reconciliation.
- Actual open/read failure retains the resolved lease URL. Missing/stale lease paths re-resolve the original bookmark before alerting; rename/ordinary `.Trash` recover, system Trash stays quiet. Other actual file-open/read failures (including nonpermission I/O failures) reach the existing loss boundary rather than being swallowed as decode errors. Cancellation is excluded. Real EIO hardware failure was not manufactured or claimed; the common actual-I/O failure branch is exercised by real POSIX denial.
- Existing standalone reconciliation now captures CURRENT input per invocation and checks it beside access guards before publish/follow/reconnect. It is not permanently latched to grant activation, so later foreground reconciliation after a rejected input remains live.
- Probe cancellation/retirement accompanies existing File Grant watch/open/close/loss lifecycle. No parent enumeration, root request, polling or new persisted authorization.

## Test-first evidence

All heavy commands were serial foreground RAM wrapper -> heavy-lock -> one command. No GUI app launch or device run.

1. Only compiling WI-4 stubs preceded initial RED: optional callback property with no delivery, and empty report Task with no I/O/presentation side effect. Existing WI-3 implementation/docs were intentionally already present; the receipt MEDIUM dirty-source note is not hidden. Exact stubs: `.build/i233-r2-red-CanvasWindowController.swift`, `.build/i233-r2-red-InspectorMetadata.swift`.
2. Initial targeted unit RED: **4 tests, 3 failed, 14 assertion issues**, `.build/i233-r2-unit-red.log`. Current/callback/reentrant behavior rejected the stub; cancellation remained correct.
3. Xcodegen ran AFTER adding the new App test file; build-for-testing passed. New receipt **P2-08c-T6-WI-4**, `app-red`, full bundle, both NEW spec files comma-separated: **2/170 assertion failures**, `.build/i233-r2-record-red.log`. No new behavior preceded this genuine RED.
4. Initial implementation: targeted unit **4/0**, raw App **170/0**, `.build/i233-r2-unit-green.log`, `.build/i233-r2-app-green.log`.
5. Approved ADDITIVE old-reconcile/input-only assertion was written before its guard fix: release A held header while B admission remains held, observe completed I/O and generation/replacement state. Raw RED **1/170 failed, 6 issues**, `.build/i233-r2-reconcile-input-red.log`: old reconcile changed A generation, cleared identity and discarded B. Pre-fix source `.build/i233-r2-before-reconcile-input.swift`. Per-invocation input guard then yielded **170/0**, `.build/i233-r2-reconcile-input-green.log`.
6. Initial receipt verify ran full bundle and returned `Specification held for P2-08c-T6-WI-4 — no recorded line changed between red and green.` `.build/i233-r2-verify.log`.
7. Approved ADDITIVE rejected-input liveness / callback snapshot / stale lease recovery cases were written before their fixes. Snapshot unit RED **1/5 failed, 4 issues**, `.build/i233-r2-snapshot-unit-red.log`. Native RED **2/172 failed, 24 issues**, solely the two new functions, `.build/i233-r2-fresh-read-red.log`. Pre-fix sources `.build/i233-r2-before-reader-renewal-CanvasWindowController.swift` and `...-InspectorMetadata.swift`.
8. Final targeted unit GREEN **5/0**, `.build/i233-r2-snapshot-unit-green.log`; final build-for-testing PASS `.build/i233-r2-fresh-read-green-build.log`; final raw App GREEN **172 tests in 2 suites passed after 38.827 seconds**, `Tests run: 172, Failures: 0, Errors: 0, Skipped: 0`, `.build/i233-r2-fresh-read-green.log`.

## Specification separation

No recorded assertion/line was changed or removed. Later cases and assertions are ADDITIONS. The CLI had already settled WI-4 before additive cases, so an additional CLI invocation would short-circuit and is not misreported as a fresh test run. A read-only audit using the plugin's actual `fingerprintFiles`, `diffFingerprints` and `verifyReceipt` recomputed the current comparison without changing receipt state: **SEPARATION-HELD**, modified=0, removed=0, unknown=0. Native spec +162 lines and unit spec +20 lines, every recorded line intact. Evidence `.build/i233-r2-final-fingerprint-audit.json`, backed by the actual final 172/0 run above.

Older WI-1/WI-2/WI-3 history remains untouched in its original report/receipts. No prior frozen report/assertion was edited to accommodate WI-4.

## Ledger and remaining gates

Only ACCESS-03 limitation text changed; status/acceptance prefix remains byte-identical. Generated HTML includes approved current-reader forwarding, rejection liveness, per-read fixed callback context and stale-lease recovery; no pending-owner claim remains. Actual powerbox panel acceptance remains **NOT VERIFIED**. POSIX refusal is not TCC revocation, manually posted wake is not physical sleep/wake, and quiet Trash full chrome-AX behavior is not claimed.

Root still runs full package/coverage, LCOV 100% lines/functions, remaining build/node/ledger/diff gates and final independent review. Targeted unit success is not represented as full coverage. No commit/push/PR/device status upgrade was performed here.

## Final source fingerprints

- `App/CanvasWindowController.swift`: SHA256 `d001e56edf5b8e8a4f35d8e0e21fe589ea23a596950c4dcdbf9a923d764111b1`
- `Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorMetadata.swift`: SHA256 `b9f462c11607ac42b87f1db51c6c79625b58146355a4033a1353dcaa37d67d14`

## Open questions

No owner scope decision remains open. Full coverage/final gates and independent review are pending root execution. Signed device/powerbox/TCC/physical sleep checks remain deferred as disclosed.

## Root WI-4 completion gates before per-WI commit
Fresh full package run: 1,294 tests in 36 suites PASS (.build/i233-r2-final-package.log); LCOV export PASS. Exact single report: 14,167/14,167 lines and 2,736/2,736 functions, statements 100%, branches unmeasured/threshold0. Independent coverage audit PASS in coverage-20261030-i233-r2.md. CVC/InspectorMetadata source hashes match the frozen implementation. WI-3 snapshot committed as 9b5fb4a0; this WI-4 commit follows before remaining native/tooling gates and final review, as directed by the amendment approval. Reports are included under the existing tracked repository convention.

## Final root gates and review
- Full package: 1,294 tests in36 suites PASS; .build/i233-r2-final-package.log.
- Exact package LCOV:14,167/14,167 lines and2,736/2,736 functions, statements100%; branches unmeasured/threshold0. Independent coverage audit PASS.
- xcodegen PASS; .build/i233-r2-gate-xcodegen.log.
- Native build ** BUILD SUCCEEDED **; .build/i233-r2-gate-build.log.
- Full App gate after per-WI commits:172tests,0failures/errors/skips; .build/i233-r2-gate-app.log.
- Tooling:57tests,55pass,0fail,2documented skips (real mdpro script unset); .build/i233-r2-gate-node.log.
- Ledger generated view --check PASS; .build/i233-r2-gate-ledger.log. Markdown only ACCESS-03 limitation changed; acceptance/status prefix preserved.
- Committed-range whitespace check PASS. Forbidden folder-root handleAccessLoss body is byte-identical to the base.
- Final review APPROVED:High0/Medium0/Low0; review-20261030-i233-r2.md. This supersedes the historical pre-amendment BLOCKED verdict.
- Required commit-gate refresh:1,294tests/36suites PASS; .build/i233-r2-commit-unit.log; LCOV re-export unchanged100%L/F (.build/i233-r2-commit-lcov.log). No source/test changes followed these gates.
- Mutation disabled; critical paths not configured; no push-trigger lanes configured. Actual powerbox accepted selection, signed-device parity/true TCC revocation and physical sleep/eject remain NOT VERIFIED/non-implementer follow-up.
