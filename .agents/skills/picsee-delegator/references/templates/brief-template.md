# <implementer> task: <WP or #issue> — <one-line summary> (delegator, <date>)

You are **<implementer>**. New task, fresh session. Worktree `~/Documents/mac-app/picsee-wt/<implementer>`.
Branch: `git fetch origin && git switch -c <branch> origin/main` (main ≥ <sha7>). Issue #<n>.
Tier **<Low|Medium|High>** because <reason>. Until the user explicitly restores Opus, every tier receives independent `gpt-auditor` review.

## Read first
- `AGENTS.md` (binding: test-first, named-path staging, commit format, ledger md+html, heavy lock, dangerous commands).
  Codex loads it itself; tell Kimi explicitly.
- `docs/feature-ledger.md` rows <IDs>; plan section <WP>; ADRs <list>; `docs/validation/P<n>.md` §<WP>.
- `gh issue view <n>`. User decisions to honour, quoted: 「…」.
- If UI changes: [`docs/agents/ui-parity-contract.md`](../../../../../docs/agents/ui-parity-contract.md), `design/DESIGN.md`, native mapping, and the exact HTML states mapped in plan §1.3.

## Today / wanted
<what happens now, with evidence (file:line, device run); what must happen instead>

## UI design contract (required for user-visible UI; otherwise write `无 UI 变化`)

Use [`docs/agents/ui-parity-contract.md`](../../../../../docs/agents/ui-parity-contract.md). Before coding, pin the design Git tree OID plus HTML/manifest SHA256 and list **each** affected `states/manifest.json` name, HTML path, viewport, appearance, plan §1.3 work package, ledger ID and native entry point. Split wide/compact, light/dark and visible/hidden states into separate rows; mark states outside this work package `PENDING`, not passed.

| State / HTML | Design hashes | Viewport / appearance / scale | Native user path + fixture | Ledger / WP | Native exception + source | Proof / remaining limits |
|---|---|---|---|---|---|---|
| `<manifest name>` / `<states/file.html>` | `<tree OID; HTML SHA256; manifest SHA256>` | `<width×height; light/dark; @1x/@2x>` | `<steps + deterministic input>` | `<ID / Pn-nn>` | `<specific mapped exception or 无>` | `<region/behavior/focus/a11y/zh-en checks; NOT VERIFIED items>` |

Define comparison regions, measurement coordinates and any dynamic-data masks before seeing the App screenshot. Implement from the design token/component contract; do not treat browser mockup clicks as native behavior. Device evidence requires a signed sandboxed App at matching viewport/appearance and raw reference/native PNGs tied to source/build SHAs outside the repo. A visual match alone never upgrades the ledger to `Shipped`.
List every changed reachable state and required viewport/appearance/scale/language/action as a pre-merge gate. The independent device verifier and gpt-auditor must mark each required condition `PASS` against this PR head before merge. `FAIL` or `NOT VERIFIED` blocks merge; `PENDING` requires an unreachable state and named future work package.

## WI-0 — probe the risky seam first (only if an assumption needs the device)
<exact probe; throwaway code allowed, never committed; what to record; "if it can't be delivered, record NOT VERIFIED
and continue"; "if <bad outcome>, stop and report — that is High">

## Acceptance
- AC-1 … (each testable, tied to ledger rows)
- AC-n Ledger: only text after 「限制：」 may change; never above Partial without a device record; md+html in the same
  commit (`node scripts/ledger/build.mjs`); acceptance sentences are the delegator's (separate commit quoting the user).

## Ownership
**You own, and may edit:** <files / exact hunks>. **Not yours:** <files>. Shared with <other implementer>: <split>.
If a needed change crosses a fence: stop, propose the minimal hunk, ask in your final reply.

## Test-first
- Codex: `$tdd-guardian-workflow` (plan → design tests + spec adversary → per-WI RED receipt → implement → verify →
  coverage). Receipt IDs `<WP>-WI-n`.
- Kimi / no plugin: write the tests first; run only them
  (`scripts/heavy-lock.sh swift test --package-path Packages/PicseeKit --filter <Name>`); paste the FAILING assertion
  output (not compile errors) in the handoff; implement; rerun the same filter; paste GREEN.
- Changing an existing assertion: only where it asserts the old behaviour; list before/after/why.

## Gates (paste decisive lines)
```sh
export PATH=$HOME/.picsee/tools/xcodegen/bin:/opt/homebrew/bin:$PATH DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
scripts/heavy-lock.sh swift test --package-path Packages/PicseeKit --enable-code-coverage
sh scripts/tdd/swift-lcov.sh      # coverage/lcov.info: sum LF/LH and FNF/FNH → 100% lines and functions
xcodegen generate
scripts/heavy-lock.sh xcodebuild build -scheme Picsee -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath .build/dd-ci
node --test --test-reporter=spec scripts/tdd/*.test.mjs scripts/ledger/*.test.mjs
node scripts/ledger/build.mjs --check
```
Only the heavy job itself goes under `scripts/heavy-lock.sh`, one command per call.

## Device smoke (implementer smoke, not validation) — only if the brief needs it
`pgrep -x Picsee` first; never kill a Picsee you didn't start; `~/Applications/Picsee.app` is off limits; no
pre-granting, no container/store edits, no system settings; list root IDs you leave behind.

## Commits
`<type>(<scope>): <summary>`; body names #<n>, <WP>, ledger IDs; trailer `Implemented-by: <implementer>`; one WI per
commit; stage named paths only. No push, PR, branch switch/deletion, `rm -r`, other worktrees.

## Handoff
`~/.picsee/herdr/<implementer>/<item>-handoff.md`: design; AC table (AC → proving test); RED/GREEN or receipts;
changed existing assertions; gates output; `git diff --stat origin/main..HEAD`; production lines per target; NOT
VERIFIED list; open questions. Reply DONE with the path.

## Open questions (defaults)
- OQ-1 … default: … — Follow each default; if WI-0 or the code contradicts one, stop and report.
