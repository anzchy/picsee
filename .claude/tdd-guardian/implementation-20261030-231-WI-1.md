# WI-1: Not Found classification and automatic Trash protection

Status: implementation and test lanes GREEN; original Swift receipt reports the explicitly accepted specification correction below. WI-2/WI-3 not started by this implementer. No commits, GUI tests, ledger edits or branch operations.

## Changes

- `AccessState.swift`: adds `notFound` cause.
- `AccessCauseClassifier.swift`: actual Trash evidence classifies Not Found, independently of bookmark resolution.
- `FileAccess.swift`: rejects actual Trash roots at initialization and acquisition, including held-session acquisition; refuses Trash descendants under otherwise readable ancestors; canonicalizes symlinks and identifies missing descendants using the actual user Trash and nearest existing mounted-volume ancestor. Ordinary `.Trash` behavior remains intact.
- `AccessMonitor.swift`: preserves Not Found through mapping, classifies saved bookmarks when startup has no published root, and recovers specific saved-bookmark evidence after probe/acquire refusal.
- New `AccessNotFoundTests.swift`: real bookmark/Trash admission, same-volume relocation/ordinary `.Trash`, finite classification cases, descendant guard and legacy-identity fallback/replacement regression.
- New App cases in `LostAccessRootCheckTests.swift`: reader/foreground/wake and mounted missing-bookmark launch; old permits revoked.
- Existing Trash classifier/gatherer expectations and two recovery expectations were deliberately updated BEFORE their RED records because #231 changes the supported cause from Unknown to Not Found.

## RED and separation

- `P2-08c-T4-WI-1`, `swift-red`: genuine assertion failure, 5/6 tests failed. Original receipt preserved in `.claude/tdd-guardian/receipts.json`.
- `P2-08c-T4-WI-1-App`, `app-red`: genuine assertion failure, 4/133 tests failed.
- App verify: GREEN lane and specification held. MEDIUM `implementation-already-present`: the new enum plus package classifier/guards existed at App RED; AccessMonitor implementation was written after App RED.
- Swift final verify: GREEN lane, **SEPARATION-BROKEN**, exit 1, exactly one specification file flagged. This is disclosed rather than re-recorded away.
- Accepted exception: the original retained-lease assertion compared `oldLease.url == f.old`. Real bookmarks use `/private/var`, while Foundation retains `/var` for the temp fixture; URL directory hints can also differ after Trash. The user explicitly approved fixture-only same-resource normalization. A new setup uses POSIX `realpath` while the root exists, and only that original assertion now compares normalized path strings against the captured physical root. No other recorded assertion changed. Diagnostic prints were removed. Requirement remains: a held lease retains its original location/authority session after the folder moves into Trash.

## Decisive verification

All heavy commands used `/Users/jack/.picsee/device/ram/with-ram.sh <tag> scripts/heavy-lock.sh <one command>` serially.

| Command / purpose | Result | Log |
|---|---|---|
| `xcodegen generate` | PASS | `.build/i231-wi1-xcodegen.log` |
| `xcodebuild build-for-testing -scheme Picsee -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath .build/dd-ci -only-testing:PicseeAppTests` | TEST BUILD SUCCEEDED | `.build/i231-wi1-app-build-green.log` |
| App receipt verify `P2-08c-T4-WI-1-App` | GREEN, separation held, MEDIUM noted | `.build/i231-wi1-app-verify.log` |
| `swift test --package-path Packages/PicseeKit --enable-code-coverage` (final source) | 1224 tests / 34 suites, PASS, 0 issues; 48.187 seconds | `.build/i231-wi1-unit-final.log` |
| `sh scripts/tdd/swift-lcov.sh` | wrote `coverage/lcov.info` | `.build/i231-wi1-lcov-final.log` |
| Configured integration filter through `node scripts/tdd/swift-lane.mjs` | 4 tests, 0 failures/errors/skips | `.build/i231-wi1-integration-final.log` |
| Original Swift receipt verify `P2-08c-T4-WI-1` with identical filter | Lane GREEN, expected HIGH separation correction disclosed | `.build/i231-wi1-verify-final.log` |

Original Swift record and final verify both used exactly:

`PICSEE_SWIFT_FILTER='t231|accessCauseTrashIsSeparateAndNeverReadable|t230ResolvableRootRefusalClassifiesWithoutGuessing|accessProbeGathererMarksFolderInTrash'`

Integration filter:

`issue73SystemScopeReadabilityReflectsRealFiles|issue73ReadableDropSessionOpensEmptyThenReplacesAndRejectsZIP|accessSystemAdapterCreatesAndResolvesRealBookmark|issue140SystemFileBookmarkFollowsSameVolumeRename`

Final exported changed-package-file coverage:

| File | Lines | Functions |
|---|---:|---:|
| AccessState.swift | 169/169 | 34/34 |
| AccessCauseClassifier.swift | 72/72 | 17/17 |
| FileAccess.swift | 775/775 | 125/125 |

No threshold audit or App source coverage claim is made by this WI report.

## Earlier attempts and limits

- First launch failed before the lane started because `.build/` did not exist for redirection; authorized creation of the output directory resolved it. No production change chased a runner failure.
- Intermediate full runs had only the same fixture path-spelling assertion failure; final run above passes.
- Real `.dmg` cross-volume Trash and signed-sandbox smoke remain NOT VERIFIED; delegated device smoke remains required.
- Explicit selection of a Trash folder is still an open composition question under brief OQ-4. Automatic admission is never weakened to allow it.
- No Not Found UI copy/strip/rebind/merge/Undo implementation in this WI.
