# WI-1: Historical Recent remapping — DONE

## Tests
- `t231Fix1HistoricalRootLocationsRemapAfterInactiveFollow`: actual bookmarks, two same-volume renames/probes while B lease held, old/intermediate/latest references, fresh and merge, exact Undo bytes.
- `t231Fix1ForegroundFollowsInactiveRootThenRebindRemapsHistoricalRecent`: B displayed, atomic fixture rename, foreground notification follows inactive A, loss, old Recent opens notFound, rebind maps child, new grid/strip and unique replacement root Recent.
- App observes committed child mapping before the normal successful scan remembers the root. Existing RecentFolderStore.add intentionally replaces a same-root Recent with the newly opened folder; the final scan therefore retains the replacement root entry rather than the child.

## Implementation
- Capture current plus newest-first `previousRoots` before transaction retirement.
- Derive each reference's lexical suffix from the first matching trusted location. Existing destination containment/probe/missing-only logic unchanged.

## RED and separation
- `P2-08c-T4-Fix1-WI-1`, swift-red filter `t231Fix1HistoricalRootLocationsRemapAfterInactiveFollow`: genuine RED 1/1 failed before production edits.
- `P2-08c-T4-Fix1-WI-1-App`, app-red: genuine RED 1/150 failed before production edits; GREEN SEPARATION-HELD.
- Swift GREEN SEPARATION-BROKEN: two probe-success preconditions changed from raw `.path` equality to `.resolvingSymlinksInPath().path` equality on both sides, while those directories exist. Observed actual `/private/var/.../renamed` versus expected `/var/.../renamed`, and same for `latest`. This is a fixture spelling correction, explicitly accepted by parent; remap, missing-only, destination-ID and Undo assertions unchanged. Original RED receipt retained, not re-recorded.
- Both receipt records note dirty ledger md/html at RED; those are parent's limitation-only changes, not existing F1 implementation.

## Verification
- `.build/i231-fix1-wi1-red.log`: Swift assertion RED.
- `.build/i231-fix1-app-red-build.log`: TEST BUILD SUCCEEDED.
- `.build/i231-fix1-app-red.log`: App assertion RED 1/150.
- `.build/i231-fix1-wi1-targeted.log`: diagnostic run showed only two spelling preconditions failing after minimal fix.
- `.build/i231-fix1-wi1-spelling.log`: exact observed bookmark-versus-fixture spelling evidence.
- `.build/i231-fix1-wi1-verify.log`: targeted lane green; separation finding above retained.
- `.build/i231-fix1-app-green-build.log`: TEST BUILD SUCCEEDED.
- `.build/i231-fix1-app-verify.log`: full App lane green, specification held.
- `.build/i231-fix1-wi1-unit.log`: 1277 tests in 36 suites passed after 51.655 seconds, coverage enabled.
- `.build/i231-fix1-wi1-lcov.log`: LCOV export.

All heavy commands serial and foreground under RAM wrapper plus heavy-lock. No GUI/device smoke, commits, push or PR. M2 untouched; M1/M3 deferred.
