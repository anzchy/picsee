# WI-2: Retryable Rebind/Undo failure feedback — DONE

## Tests written first
- `t231Fix1TransactionDiagnosticsMatchPersistenceAndRetry`: schema/write failures × Rebind/Undo; actual persisted bytes and in-memory records unchanged on handled failure, typed unsupported-version error retained, bounded transaction root/operation/stage/kind output, rollback/no-commit counts, retry state and exact Undo bytes.
- Extended `t231RebindFailureAndUndoFailureRemainRecoverable`: existing Lost Access/grid/Undo and persistence assertions retained, added exactly one root/stage/safe-kind report per failed transaction; successful retries add none.
- Extended `t231NotFoundCopyAndCancelLeaveRecoveryActions`: cancellation retains state and emits no failure report.
- Before RED, added only an inert App failure reporter property so outcome assertions compile. All reporting calls, default Logger/beep behavior, actor stages and logging were added after RED.

## Implementation
- FileAccess Rebind/Undo emit attempt, commit, rollback and error events through existing AccessDiagnostics, whose default sink is os.Logger with subsystem io.github.anzchy.picsee/category access.
- Public messages contain root UUID, bounded operation/stage/outcome and AccessDiagnostics.errorKind only. Transaction events pass no path; no bookmark bytes or raw error descriptions/domains are interpolated.
- Granular stages distinguish selection, root/Recent validation, snapshot/read, cancellation, root/Recent writes, Undo restore, rollback restore and publication. Rollback errors retain their actual stage; successful rollback rethrows the original typed error unchanged.
- Undo memory stores sourceID to correlate its events with the original Rebind.
- Active noncancelled App failures invoke an injectable failure-output closure once; default emits a safe AccessTransactionUI event and calls NSSound.beep. Existing recovery/Undo controls remain retryable. Success, stale operations and cancellation remain silent.
- No new UI, copy, dependencies or durable recovery mechanism.

## RED receipts and separation
- `P2-08c-T4-Fix1-WI-2`, swift-red filter `t231Fix1TransactionDiagnosticsMatchPersistenceAndRetry`: genuine RED 1/1 failed; final GREEN SEPARATION-HELD.
- `P2-08c-T4-Fix1-WI-2-App`, app-red: original genuine RED 2/150 failed; final GREEN SEPARATION-HELD.
- A direct raw old-binary App rerun before rebuilding showed only the intended `t231RebindFailureAndUndoFailureRemainRecoverable` failure (eight new reporter expectations, zero outputs), with 149 other tests passing. The original receipt CLI does not persist raw lane output, so its second transient failure is unidentified and is not claimed to be #290. Original receipt retained, never overwritten/re-recorded.
- No WI2 recorded line changed between RED and GREEN. Receipt dirty-source notes refer to completed WI1, parent ledger changes and the declared inert App reporter stub.

## Gates and logs
- `.build/i231-fix1-wi2-red.log`: genuine Swift RED.
- `.build/i231-fix1-wi2-xcodegen.log`: project generated successfully.
- `.build/i231-fix1-wi2-app-red-build.log`: unsigned TEST BUILD SUCCEEDED.
- `.build/i231-fix1-wi2-app-red.log`: original App RED 2/150.
- `.build/i231-fix1-wi2-app-red-detail.log`: raw old-binary RED 1/150, only intended reporter failure.
- `.build/i231-fix1-wi2-verify.log`: Swift lane GREEN, specification held.
- `.build/i231-fix1-wi2-app-green-build.log`: unsigned TEST BUILD SUCCEEDED.
- `.build/i231-fix1-wi2-app-green.log`: 150 tests in 2 suites passed after 21.857 seconds; Failures 0, Errors 0, Skipped 0.
- `.build/i231-fix1-wi2-app-verify.log`: full App lane GREEN, specification held.
- `.build/i231-fix1-wi2-unit.log`: 1278 tests in 36 suites passed after 50.925 seconds, coverage enabled.
- `.build/i231-fix1-wi2-lcov.log`: swift-lcov wrote coverage/lcov.info.

All heavy jobs ran serially in the foreground under RAM wrapper plus heavy-lock. No heavy job remains active. No GUI/device smoke, commits, push or PR. Parent owns independent coverage/review, ledger/design gates and final commits. M1/M3 remain open.
