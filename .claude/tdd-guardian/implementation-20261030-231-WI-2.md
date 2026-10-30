# WI-2: Persisted rebind, merge, Recent remap and exact Undo

Status: DONE with the disclosed non-assertion fixture setup separation finding. No commits, staging, GUI work, ledger changes or WI-3 implementation. All final verification below ran after disk space was restored; ENOSPC attempts are excluded from RED/GREEN and coverage evidence.

## Production APIs

`Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/FileAccess.swift` exposes:

- `rebind(_:folder:recentStore:existenceProbe:) throws -> AccessRebindResult`
- `undoRebind(_:) throws`
- `discardRebindUndo(_:)`
- `verifyExplicitSelection(_:) throws -> URL`

`AccessRebindResult` exposes `rootID`, `rootURL`, `undo`. Its token is session-only and one-shot after successful Undo; failed Undo remains retryable.

## Behavior

- Fresh rebind removes lost A and creates a new destination ID; merge retains existing B's ID/metadata and removes A. Matching uses renewed saved-bookmark resolution under its own scope even when B's published root was dropped.
- Old-root location comes from previously captured root location or stored bookmark path. A nested current folder is never assumed to be the root. Missing trustworthy root evidence refuses mutation.
- Recent references map by lexical relative suffix; system root spelling aliases such as /var and /private/var are normalized without resolving old descendant symlink targets. Destination symlinks resolve before containment checks. Escapes retain original unresolved references; only confirmed missing entries drop. Permission/I/O uncertainty retains references. Existing destination collision metadata/order and unrelated references remain intact.
- `RecentFolderStore` normal actor calls and synchronous transaction share locked storage, avoiding await/reentrancy between the two stores. Snapshots preserve exact primary/recovered/schema bytes and file absence. Corrupt/future schemas refuse mutation. Handled errors roll back both files before publication. No crash-atomic journal guarantee is claimed.
- Saved-grant proofs retire before persistence attempts. Undo retires every current/restored root's proof, including C granted after the snapshot and removed by exact Undo. Held leases retain their original sessions and remain releasable.
- Explicit Trash selection has session-only pinned path/inode authority for readers. Launch/probe/recovery remain automatic rejection paths; App must use normal shared root checks for Recent/foreground and reserve `verifyExplicitSelection` for the panel continuation. Ordinary roots later moved into Trash remain rejected. No File Grant expansion.
- No image pixels, decoded metadata, thumbnail state or old image identity transfer is implemented here. Fresh root ID prevents source identity reuse; App orchestration remains WI-3.

## Tests and RED

`Packages/PicseeKit/Tests/PicseeInfrastructureTests/AccessRebindTransactionTests.swift`: 22 test functions, including parameterized cases. Real persisted stores/directories/symlinks/bookmarks/Trash cover replacement, merge with dropped resolved map, relative remap, destination containment, uncertainty, failures in both persistence directions, retry/one-shot Undo, absent files/sidecars, cross-volume identity ports, relaunch location evidence, cancellation, held leases and proof retirement.

Original receipt `P2-08c-T4-WI-2` was recorded before implementation, genuine assertion failure (7/9 test functions), and was not re-recorded. Record and verify use exactly:

`PICSEE_SWIFT_FILTER='t231.*(Rebind|RecentRemap|PersistenceFailure)'`

Supplemental regressions also witnessed assertion RED before fixes:

- `.build/i231-wi2-source-alias-red.log`: old source symlink must retain its lexical relative suffix when destination differs.
- `.build/i231-wi2-proof-red.log`: root C's saved proof incorrectly admitted after exact Undo removed C.

Targeted final updated-source GREEN: 22 functions, `.build/i231-wi2-proof-green.log`.

## Final verification (after ENOSPC recovery)

All heavy jobs used serial foreground `/Users/jack/.picsee/device/ram/with-ram.sh <tag> scripts/heavy-lock.sh <single command>`, with normal shared-lock settings.

| Gate | Result | Log |
|---|---|---|
| `swift test --package-path Packages/PicseeKit --enable-code-coverage` | PASS, 1246 tests / 34 suites, 53.314 seconds | `.build/i231-wi2-complete-unit.log` |
| `sh scripts/tdd/swift-lcov.sh` | PASS, fresh `coverage/lcov.info` | `.build/i231-wi2-complete-lcov.log` |
| Configured integration lane | PASS, 4 tests, zero failures/errors/skips | `.build/i231-wi2-complete-integration.log` |
| Original WI2 receipt verify | Lane GREEN; expected SEPARATION-BROKEN, exit 1, setup finding below | `.build/i231-wi2-complete-verify.log` |

Configured integration filter:

`issue73SystemScopeReadabilityReflectsRealFiles|issue73ReadableDropSessionOpensEmptyThenReplacesAndRejectsZIP|accessSystemAdapterCreatesAndResolvesRealBookmark|issue140SystemFileBookmarkFollowsSameVolumeRename`

| Production file | Lines | Functions |
|---|---:|---:|
| FileAccess.swift | 989/989 | 153/153 |
| AccessRebind.swift | 123/123 | 20/20 |
| RecentFolderStore.swift | 64/64 | 23/23 |

This is the implementer's source coverage precheck, not the workflow's final formal coverage audit.

## Specification separation disclosure

The original receipt reports HIGH `spec-changed-under-green` for this one new test file. Exactly four non-assertion setup lines changed: the old/chosen/other fixture folder URL constructors now set `isDirectory:true`, and the folder-only Recent fixture helper constructs directory URLs. Before correction, URLs created before directories existed carried file-style URL hints, while bookmark resolution returned directory URLs with trailing slashes. Even a held lease's original URL therefore mismatched its fixture before any rebind. The correction describes the same resources and requirements. Root explicitly authorized this routine setup correction. No recorded `#expect`/`#require` line or inline expected expression changed; added cases remain additions. The original RED and finding remain intact.

The receipt also retains MEDIUM `implementation-already-present`: seven non-test paths were already modified at RED because WI-1 was staged and new WI-2 APIs required compilable throwing stubs. Those stubs had no rebind implementation; the genuine RED preceded implementation.

## Limits and next boundary

- ENOSPC failed exports/empty wrappers are environment failures, never test evidence. Only verified owned empty wrappers/samplers were cleaned; no shared locks/caches or unrelated processes were deleted.
- Signed sandbox/device/system panel interaction and actual mounted .dmg cross-volume behavior remain NOT VERIFIED.
- WI-3 must compose panel generation checks, window clearing/new identity, persistent per-window strip, Lost Access restoration and global access-state permit retirement for roots removed by exact Undo. Root owns this work and the final handoff.
