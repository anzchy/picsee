# Test matrix — issue 127 resume

Plan: `plan-20261027-issue127-resume.md`

| WI | Test case | Assertion strategy | Specification level | Boundary / integration | Law | Refactor resilience |
|---|---|---|---|---|---|---|
| WI-1 | Existing leaf validation | Level 4: enabled state | S1 | AppKit menu validation; no mock | No law | Internal parent bookkeeping can change |
| WI-2 | Empty icon omitted from AX tree | Level 1: AX child output | S3 | Real NSView; no mock | No law | Layout internals can change |
| WI-3 | JPG and JPEG filter equivalence | Level 1: projected filenames | S4: case variants equivalent | Real snapshot; no mock | Equivalence law | Internal canonicalization can change |
| WI-3 | One JPG choice and toggle | Level 1: choices/check state | S5: toggling twice restores state | Real menu policy; no mock | Toggle involution | Storage representation can change |
| WI-4 | pgrep fails after spawn | Level 2: owned child stopped, no record | S3 | Mock OS process boundary; real device path remains separate signed device suite | Ownership invariant | Launch internals may change if ownership stays provable |
| WI-5 | UI body missing/empty/filled table and non-UI body | Level 1: lint verdict | S2/S3 | Real parser; CLI Git boundary exercised locally | No law | Parser internals can change |

Adversarial check: Wrong implementations that treat JPEG and JPG as separate fail the projection and menu tests. A launcher that only catches pgrep without owning a child fails the owned-child assertion. A heading-only lint fails the empty-table case. No known specification gap remains for the Low scope.
