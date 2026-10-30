# Implementation — P2-08c T4 WI-3

Status DONE (before root final gates/review).

App NotFound copy/actions, captured panel meaning, per-window rebind/merge/Undo state, native strip/layout/focus/lifecycle, explicit-selection monitor admission with grant/request/counter/mount fences, global removed-root retirement, readable merge-target authority preservation. Five new string catalog entries only; original formatting retained.

Narrow infrastructure addition: automatic probeRootURL rejects Trash before acquire, regardless of session explicit selection; genuine supplemental RED P2-08c-T4-WI-3-AutomaticTrash preceded fix. Explicit user grant/rebind still admits its pinned path/inode session; automatic launch/recovery/probe never uses that exemption.

Evidence: unit1247/34 suites PASS; App148/148 PASS; configured integration4/4 PASS; changed package production1420/1420 lines247/247 functions. Logs .build/i231-wi3-{unit,coverage,integration,app-green,app-verify,trash-red,trash-verify}.log. Original P2-08c-T4-WI-3 App RED4/139 failed assertions, original and supplemental receipts SEPARATION-HELD. No recorded assertion changed. Initial NSWindow fixture ownership crash produced no valid RED and was corrected before genuine recording. Later added explicit-Trash controller test had a readiness-predicate timeout caused by raw NSURL directory-hint equality; completed scan, same path, visible grid and item count now asserted; no production fix was required for that fixture correction. ENOSPC failures from prior WI never count as evidence.

Named tests in AppTests/LostAccessRecoveryTests.swift and AccessRebindStripTests.swift cover copy/cancel/catalog, fresh+merge exact Undo, chooseOther preservation, global later C permission retirement, B permit preservation, failed persistence/Undo retry, stale navigation/window close, postcommit target-read failure retaining strip, close/resize/native Tab, and actual explicit Trash rebind to visible grid then foreground NotFound and Undo. Supplemental package test in AccessRebindTransactionTests.swift covers automatic Trash probe.

Frame source: page26 pinned Unknown rules, spec #227/#231 copy. Icon32; title16 medium; detail13/22.1 max460; icon/title18, title/detail9, detail/actions18, actions gap16. Real shell both1280x800/800x680, light/dark and both languages. Strip no pinned state: DESIGN.md tokens height44, controls28, inset16, gaps8, middle truncation, above content, AX close/full text and focus retirement. App-only view avoids Grid/** edits.

NOT VERIFIED: signed sandbox smoke/system panel operation, pixel parity, real VoiceOver, @2x and actual cross-volume device flow. Delegator owns device smoke. No commits/push/PR/GUI tests by implementer. Root owns final ledger, final gates, independent audits, per-WI commits and final handoff.
