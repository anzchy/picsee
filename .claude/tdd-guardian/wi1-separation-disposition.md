# P2-01 WI-1 separation finding disposition

Owner: gpt-imple-1 (implementation coordinator), not a user approval or a claim of SEPARATION-HELD.

Original receipt P2-01-WI-1 remains SEPARATION-BROKEN and is never overwritten. The historical High spec-changed-under-green finding is retained. Policy-core completion gates 8 and 10 permit a stated reason for recorded test-file edits and resolution or explicit waiver of High findings with rationale. This document explicitly waives that setup-only High for continued implementation, subject to final review and the two delegator-owned blind audits.

Rationale: nine directory URL construction inputs gained isDirectory:true after the first full run demonstrated URLs differing only by trailing slash. All 57 #expect lines are byte-identical to the saved RED tests. No production code changed for this correction. Inputs now explicitly describe the directories the scenarios always required; ID preservation, exact folder boundaries, failure atomicity, scoped ordering, and lease expectations are unchanged. The original RED, initial failed run, original test snapshot, and exact nine-line correction diff remain in external evidence. Retry:327 tests passed including19 WI1 scenarios. A separate interim reviewer found no independent code/test defect and confirmed all assertions unchanged.

The compilable-stub implementation-already-present MEDIUM is documented: only the throwing stub/new error existed at RED, with snapshot evidence. This disposition does not waive changed assertions, any later finding, sandbox restrictions, coverage, native smoke, future WI receipts, or final reviews. The implement skill's fresh-user-acceptance condition for changed assertions is not triggered because none changed.
