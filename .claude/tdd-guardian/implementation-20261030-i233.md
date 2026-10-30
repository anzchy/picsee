# #233 implementation: successor WI-3

## Current status

Original owned implementation is App GREEN with SEPARATION-HELD. Controlled reverts have been restored byte-for-byte. The whole issue is **not complete**: owner approval for Inspector-only / generic-loader access-failure forwarding remains pending, and the additional reader hooks remain outside the approved fence. Root completed the executable final gates below; final review and overall completion remain pending. No commit, push, PR, rebase, destructive command, GUI app launch, or device/status upgrade was performed.

## Tests written

- `AppTests/Issue233FileGrantLossTests.swift`: 7 native tests covering held rename (#257 equivalent), decode-first removal/held old reconcile/cancel, wake and vnode loss/lifecycle, real AppDelegate foreground POSIX denial, alert/panel cancel and accepted same/different URLs through the shared continuation, superseded reconcile/live stale panel completion, and reconcile loss before sheet/repeated hints. Decode/reconcile cases assert full native cleared state inside `NSWindow.willBeginSheetNotification`.
- `Packages/PicseeKit/Tests/PicseeInfrastructureTests/Issue233FileGrantBoundaryTests.swift`: real PNG/watch descriptor/image read/failing retry through the existing AccessLeasing seam; file-only lease requests, balanced leases, descriptor closure, no root store. Authored; package execution remains root-owned.
- `Packages/PicseeKit/Tests/PicseeApplicationTests/Issue233InspectorLossTests.swift`: clear selection before held metadata/thumbnail completion; no stale model result. Authored; package execution remains root-owned.

## Production implementation

Only owned hunks in `App/CanvasWindowController.swift` changed:

- `requestFileReconnection`: synchronous loader/Inspector/title/proxy/canvas/native filename AX clearing before any sheet guard; access/input invalidation; retire grant/watch/wake/reconcile hints. Inspector hosting is hidden immediately.
- `completeFileReconnection`: actual panel completion and native acceptance tests share the ordinary `openInput` continuation, guarded by original URL and both access/input authority. Cancel consumes the recovery context; stale completions cannot reopen A after B.
- Reconcile: a real one-byte FileHandle read inside the existing file lease proves current readability before ImageIO can erase errno into a generic decode failure. Permission denial enters the shared loss boundary. Existing readable corruption, bookmark re-resolution, rename and quiet Trash policies are preserved.
- File Grant watcher: an RAII wake token with weak self/current operation/current grant checks; cleanup beside existing watch cleanup in open/close/openFolder/folderScanDidStart. Folder-root handleAccessLoss was not edited.

Current source SHA256: `65dd4dfa380744c546c904c3db1ae9bbb22e213faa98abb3360bce76fb59f7e3`. Exact saved implementation: `.build/i233-implemented-CanvasWindowController.swift`.

## Genuine RED / harness correction history

The correction history is explicit; these are not represented as an untouched initial test specification.

1. Initial attempt: environment failure at `NSSavePanel.ok:` / SIGABRT. Stopped before implementation. Invalid receipt archived as `.build/i233-invalid-environment-receipt.json`; log `.build/i233-record-red.log`. The initial space-separated `--files` also fingerprinted only the first path. Delegator `i233-unblock.md` approved replacing impossible xctest powerbox acceptance with real panel config/cancel plus the existing folder-style internal continuation. Actual powerbox acceptance remains NOT VERIFIED.
2. WI-1: genuine assertion RED, 5/166 failed. Raw repeat `.build/i233-red-output.log` confirmed failures were only new #233 cases but exposed an Inspector command requested before any image was open. Root authorized moving the SAME command assertion after the first settled image; no product acceptance weakened. Original WI-1 receipt remains unchanged and superseded.
3. WI-2: genuine assertion RED, 5/166 failed (`.build/i233-wi2-record-red.log`). After implementation, readable POSIX-denied files required the real leased byte read. Native scope diagnostics then proved bookmark resolution returned `/private/var/...` for the selected `/var/...` file; no directory scope occurred (`.build/i233-readable-app.log`). Root authorized canonical comparison of both actual and expected selected file URLs, also in the package request URL assertion. Original WI-2 receipt remains unchanged and superseded.
4. WI-3: saved implementation, temporarily used original HEAD plus ONLY the no-op continuation stub, built, then genuine assertion RED: **5/166 failed**. All three test paths were comma-separated and fingerprinted. Log `.build/i233-wi3-record-red.log`; reconstructed exact scaffold `.build/i233-wi3-red-scaffold.swift`; original source `.build/i233-original-CanvasWindowController.swift`. Restored the saved implementation with identical SHA. Canonical scope comparison needed an existing original path for Foundation alias resolution; root approved an ADDITIVE stronger transition: recreate the original after accepting portrait, assert portrait remains/no sheet, then run the frozen comparison. No WI-3 recorded line changed. Temporary added diagnostics were removed; evidence remains in `.build/i233-reappearance-app.log`.

The alias correction was discovered after implementation and is not claimed to be blind test design. Core privacy assertions had genuine RED before the original implementation and remain unchanged. The expected MEDIUM `implementation-already-present` note is the permitted no-op compiling stub, not the behavior implementation.

## Verification

All heavy jobs ran serially as `/Users/jack/.picsee/device/ram/with-ram.sh <tag> scripts/heavy-lock.sh <one command>`.

| Evidence | Result / log |
|---|---|
| New tests / restored implementation build-for-testing | PASS, `** TEST BUILD SUCCEEDED **`; latest `.build/i233-restored-build.log` |
| Raw full App GREEN before mutants | `166 tests in 2 suites passed after 35.885 seconds`; `Tests run: 166, Failures: 0, Errors: 0, Skipped: 0`; `.build/i233-reappearance-app.log` |
| WI-3 verify | PASS / SEPARATION-HELD: `Specification held for P2-08c-T6-WI-3 — no recorded line changed between red and green.` `.build/i233-wi3-verify.log` |
| Controlled revert | Expected assertion failures: 166 tests, 7 failed, 119 issues; `.build/i233-controlled-app.log` |
| Restore | Exact production SHA matched saved implementation; rebuilt successfully |
| Final WI-3 verify invocation | Existing settled receipt short-circuited (`Nothing new to verify`), so it was NOT misreported as a fresh test run; `.build/i233-wi3-final-verify.log` |
| Explicit raw full App after restore | PASS: `166 tests in 2 suites passed after 34.556 seconds`; `Tests run: 166, Failures: 0, Errors: 0, Skipped: 0`; `.build/i233-final-restored-app.log` |

Historical WI-1/WI-2 are superseded evidence, not SEPARATION-HELD claims; final separation is WI-3. Unit/coverage/build/node/full ledger checks remain root-owned and are not claimed here.

## Controlled-revert evidence

Manifest `.build/i233-controlled-revert-manifest.json` records base SHA above and mutant SHA `9073f7c6d83fb89e3a9406ebbeb26af454a4302c98b6e2940d9c5f5d5d39ecff`. No test changed during mutations. Three surgical owned mutations were combined in one full App run:

- Omit the existing presentation clear helper in the central loss boundary: full cleared-state assertions fail in decode-first, reconcile, wake/vnode and foreground cases.
- Omit the existing normal-open continuation: accepted portrait URL, representedURL and aspect-ratio assertions fail (native test lines 354/355/360 in that run).
- Disable failed-read bookmark follow: `issue233HeldRenameDuringHeldReconcileReadFollowsWithoutSheet` and existing `issue273DotTrashMoveDuringReconcileReadFollowsWithoutSheet` fail.

The seven failed cases are those two rename cases plus decode-first, wake/vnode, foreground, reconnect selection/cancel and reconcile loss. Superseded failure remains silent. No forbidden AppDelegate, loader/Inspector package or infrastructure production mutation was used. Restored source exactly before rebuilding and the final 166/0 raw run.

## Per-AC map and honest limits

- AC-1: original owned non-Trash detection paths clear synchronously before sheet and reject held old reconcile work; model/loader generation laws are reused. **Inspector-only and generic loader errors on still-existing files are not yet forwarded**; see pending owner amendment. Metadata late-result package test has not yet run in this stage.
- AC-2: real file-panel configuration/cancel, selected-file-only native scope history, no root store; package lease-kind/read/release test awaits root execution. Picsee does not enumerate the parent.
- AC-3: same/different accepted URLs use the same production continuation and settle actual image identity/dimensions; alert/panel cancel stays clear; live stale A context is invoked only AFTER B supersedes it, before panel cancellation, then again after cancellation. Actual powerbox acceptance is NOT VERIFIED and belongs to non-implementer device smoke.
- AC-4: 166/0 includes existing #273 Trash, #140 ordinary `.Trash`, held rename and stale operation regressions. Quiet Trash path itself was not expanded; full-cleared chrome AX behavior for that existing path is not claimed.
- AC-5: ACCESS-03 limitation only, status/acceptance prefix preserved, generated HTML updated. Root runs final sync/check gate.

## Pending amendment / final work

Root requested owner approval at `/Users/jack/.picsee/herdr/gpt-imple-1/i233-amendment.md` for a minimal InspectorModel post-generation-guard failure callback plus Canvas initializer/loader forwarding into a stamped access-only probe. A readable corrupt file must remain an ordinary decode/metadata error, not cause an open/reconcile loop. No added production hook was written while approval was pending.

True sandbox/TCC revocation, physical sleep/wake/eject, real powerbox acceptance and signed device parity remain unverified. POSIX chmod denial and manually posted wake notification are named accurately. Final package coverage and other brief gates, overall issue completion, commit and handoff are root-owned.

## Root final executable gates
- Package coverage run: 1,289 tests / 36 suites PASS; .build/i233-final-package.log. Both new package cases passed.
- LCOV export PASS; exact single report: 14,164/14,164 lines and 2,736/2,736 functions (100%); statements 100%, branches unmeasured with threshold 0. Independent coverage auditor PASS; .claude/tdd-guardian/coverage-20261030-i233.md.
- xcodegen generate PASS (.build/i233-gate-xcodegen.log).
- xcodebuild build PASS, ** BUILD SUCCEEDED ** (.build/i233-gate-build.log).
- Required final full App gate: 166 tests, 0 failures/errors/skips (.build/i233-gate-app.log).
- Node tooling: 57 tests, 55 passed, 0 failed, 2 documented skips (.build/i233-gate-node.log).
- Generated ledger check PASS (.build/i233-gate-ledger.log).
- git diff --check and origin/main..HEAD check PASS (committed range still empty).
- Controller SHA independently confirmed exactly 65dd4dfa380744c546c904c3db1ae9bbb22e213faa98abb3360bce76fb59f7e3; ACCESS-03 is the only changed Markdown row, status/acceptance prefix unchanged.
- No additional reader-hook approval received yet. Overall AC-1/next-access completeness remains pending; no claim that whole #233 is complete.

## Final review / stop
TDD review: BLOCKED, one High finding — AC-1/next-access discovery remains incomplete for Inspector-only and generic loader failures on a still-existing File Grant. Review: .claude/tdd-guardian/review-20261030-i233.md. The original owned patch has no additional concrete defect; tests are behavioral and WI-3 separation held. No commit or commit-gate refresh follows a blocking review. Owner approval for i233-amendment.md is still required before the extra production hunks.
