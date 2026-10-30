# Implementation record — #230

WI-1, WI-2 and WI-3 implemented. See external i230-handoff.md for final evidence.

## Recorded-specification corrections

- Original WI-3 App receipt superseded after correcting the OS bookmark fake: an old bookmark and a newly created bookmark for a replacement at the same path must have distinct tokens/identities. All #expect acceptance assertions retained.
- WI-3 APP-FIXTURE receipt mechanically SEPARATION-BROKEN because the constructor gained `selectionScope: bookmarks` after RED. Removing only that argument reconstructs recorded SHA8187ed90487d062b36e70a3bebd04be9116894fa6ccaf0b24d5a46d513d6e463 exactly. Independent reviewer accepted this as explained fixture wiring, not a changed acceptance claim.
- Round-1 final review found the new WI-1 mixed lifecycle test's exact mount-count assumption invalid: Task.yield does not prove notification task entry. The production behavior did not change. Replaced that supplemental scheduling assertion with observable loss event counters plus stale-report idempotence. Existing deterministic #229 coalescing assertions remain unchanged. This intentionally changes recorded WI-1 App test lines with a stated reason: the original supplemental scheduling specification was wrong, not an implementation needing a weaker acceptance target. No re-recording after green.

Whole-project shortcut coverage gap is explicitly delegated to a separate issue by the user. #230 accepts 100% lines/functions for changed package source files; configuration and raw global FAIL remain unchanged.
