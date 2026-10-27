# TDD plan — issue 127 resume

## Work Items

### WI-1: L1 submenu parent cleanup
Acceptance: ineffective parent `isEnabled` assignments removed; leaves retain validation.
Tests: existing command-menu validation tests; no changed behavior expected.

### WI-2: L5 empty-state accessibility
Acceptance: empty-state icon absent from AX children; error icon remains meaningful.
Tests: `issue92EmptyStateComposesSemanticContent` and viewer-state layout suite. RED receipt ISSUE127-WI-5 was recorded by prior implementor.

### WI-3: L6 JPEG extension group
Acceptance: one JPG menu choice covers both .jpg and .jpeg in any case; other types remain.
Tests: `issue127Jpeg*` tests. RED receipt ISSUE127-WI-6 was recorded by prior implementor.

### WI-4: L3 device launch ownership
Acceptance: a post-launch pgrep failure terminates only this run's child; no unowned Picsee remains.
Tests: fake pgrep regression in `process_query_test.py`; red was observed before implementation.

### WI-5: M6 UI-Parity body lint
Acceptance: local script fails a UI PR body without a populated `## UI-Parity` table; non-UI changes pass.
Tests: Node CLI policy unit tests; red was observed before implementation.

## Deferred / Out of Scope

L2 and L4 already match current main. No GUI or signed device run in this task. No CI wiring.
