# Doc gardening: keeping the feature ledger true

This is the single procedure for the picsee doc gardener. Two thin wrappers load it:
- `.claude/agents/picsee-doc-gardener.md` for Claude Code;
- `.codex/agents/picsee-doc-gardener.toml` for Codex.

Change the procedure here, never in a wrapper.

**Why it exists.** `docs/feature-ledger.md` is the system of record for what picsee can do. The rule is that
the commit that changes a behaviour also rewrites its row. The ledger's own gate can't tell whether a
sentence is still true, and authors forget. The gardener runs on every PR and catches the rows the
change made stale. This follows two published practices:
- OpenAI's harness-engineering team runs a recurring doc-gardening agent that scans for stale docs and
  opens fix-up PRs, because repository knowledge is the system of record;
- Anthropic's long-running-agent harness lets an agent change a feature's status only after it has
  verified that feature end to end, and forbids removing or editing tests.

## When it runs

| Mode | Trigger | Range |
|---|---|---|
| `pr` | **Before every PR is opened, and again before each re-push of a PR head.** Whoever opens the PR runs it: the delegator under rule 70, or any session or person running `gh pr create` | `git merge-base main HEAD`..`HEAD` |
| `full` | When the user asks, or when an area in the ledger's Part 3 table is more than 30 days past its last review and code in it has changed | the whole ledger against the working tree |

A PR is not opened without a gardener verdict for its head. The PR body carries the verdict line (see Output).

## What you may change, and what you may only propose

The asymmetry is the point. **You may make the ledger more cautious, never more optimistic.**
A wrong downgrade costs one re-check. A wrong upgrade is the false claim the ledger exists to prevent.

**Apply yourself.** These are edits to `docs/feature-ledger.md` only:
1. **Moved paths.** A path in 在哪 that the range renamed (`git diff -M`) is rewritten to the new path.
2. **Deleted paths.** A path the range deleted is removed from 在哪. If that leaves a non-`Absent` row with no path, don't
   guess: report it as NEEDS-OWNER.
3. **Lost evidence.** A row whose linked `docs/validation/` record no longer exists, or no longer mentions
   the row's ID, is downgraded:
   - 验证 drops to the strongest evidence that remains;
   - `Shipped` becomes `Partial`;
   - one sentence is appended to 怎么确认: `限制：真机记录缺失（<file>），待复验。`

   Nothing else in that cell changes.
4. **Broken links.** A link to a renamed file is repointed. A link with no target is reported, not deleted.
5. **Area review.** For each ledger area the range touched, set its Part 3 row to today's date and reviewer
   `doc-gardener`. Note any finding in that row's 备注 cell.

**Propose only.** Write these into the report for the owner. Never edit them yourself:
- any state or 验证 upgrade, whatever evidence you see;
- a new row, for a new capability or for a declared name with no row;
- any change to 能力, or to 怎么确认 beyond the sentence allowed in step 3;
- moving a row to 不做, or back.

## Procedure

1. **Inputs.** You need the mode; for `pr`, the branch's worktree path, the base and the head SHA; and the
   PR's ID or branch name. Anything missing returns BLOCKED.
2. **Read** `docs/feature-ledger.md` in full: its rules first, then its rows. Read the work package IDs in
   `docs/PICSEE_DEVELOPMENT_PLAN.md`.
3. **Collect the change.**
   - `git diff --name-status -M <base> <head>`
   - `git log --format='%H %s%n%b' <base>..<head>`
4. **Map the change to rows.** A row is *touched* when any of these holds:
   - **path**: a changed file is in its 在哪 cell, or under a directory named there;
   - **ID**: the row ID appears in a commit message, a changed test's name or path, a changed
     `docs/validation/` file, or the branch name;
   - **plan**: a work package ID in a commit message or the branch name is in its 计划 cell;
   - **surface**: a changed file adds or removes a declared name, meaning a CommandRouter command ID, a
     menu item identifier, a `DisplayPreferences` key, an entitlement, or an `Info.plist` UTType. Use the
     source tree layout in `docs/PICSEE_ARCHITECTURE.md` to find them.
5. **Judge each touched row.** Each row lands in exactly one of these:
   - **Updated.** The range already edits that row consistently.
   - **Stale.** Behaviour on the row's paths changed, but the row did not. Propose the edit: the new state,
     a 限制 if needed, and the evidence. Check the claim against the code at `<head>`, not the commit
     message.
   - **Unaffected.** The change provably has no user-visible effect, such as a pure rename, a test-only
     change, or a comment. Give the reason in one line.
6. **Integrity checks across the whole range:**
   - **Weakened acceptance.** In the same range, a row's state or 验证 went up **and** the acceptance
     itself in 怎么确认 was rewritten. This verdict is BLOCK. Appending or editing `限制：` text does
     not block; any acceptance rewrite goes in a separate commit that cites the user's words or an ADR.
     状态升级的那次提交，可以追加或修改「限制：」文本，但不得改写「怎么确认」中的验收本身。确需改验收时，单独提交并在提交说明里引用用户原话或 ADR。
   - **Upgrade without evidence.** A row became `Shipped` without `验证 = 真机` and a `docs/validation/`
     link that exists and mentions the row ID. This verdict is BLOCK.
   - **Entry points not all verified.** A row went up to `验证 = 真机` or `Shipped`, but its 怎么确认 lists
     several entry points or values (joined by 或, /, 、) and the linked `docs/validation/` record has no
     verdict line for one of them, or marks one NOT VERIFIED. This verdict is NEEDS-OWNER: the row stays at most
     `Partial`, with a `限制：` naming the unverified entry point.
   - **No second view.** A row went up to `真机` or `Shipped`, its 怎么确认 claims persistence (保留, 退出重开,
     记住), a file write (导出, 另存, 去除元数据) or a release (释放), and the validation record shows no
     relaunch, no read of the written file, or no log line respectively. This verdict is NEEDS-OWNER.
   - **Self-certification.** Every commit here can share one git author, so authorship proves nothing; the
     check reads commit trailers instead. For each row that went up to `真机` or `Shipped`, find the commit
     that added or changed its `docs/validation/` section. It is self-certification, and the verdict is
     NEEDS-OWNER, when any of these holds:
     - that commit has no `Validated-by: <role> run=<run-id>` trailer;
     - the role in it also appears in an `Implemented-by: <role>` trailer on a commit in the range that
       touches the row's paths;
     - the same commit also changes source code (anything outside `docs/`).

     The record must come from the device tester, in its own commit.
   - **Format.** Every touched row must also pass the ledger's format rules:
     - state and 验证 are in their enums;
     - a `Partial` row carries `限制：`;
     - an `Absent` row has `—` in 在哪;
     - no path has a line number, a count or a build output;
     - 怎么确认 is no longer than three sentences or about 150 characters.
7. **Apply** the edits you are allowed to make, in `docs/feature-ledger.md` only. Do not stage or commit.
   The caller reviews `git diff -- docs/feature-ledger.md` and commits it as
   `docs(ledger): garden <base7>..<head7>`.
8. **Write the report** to `~/.picsee/gardening/<branch>-<head7>.md`, creating the folder if needed, and
   return it as your final message.

In `full` mode, take the base as the commit that last touched each area's Part 3 row, then run steps
4–8 for each area.

## Boundaries

- Edit nothing but `docs/feature-ledger.md`. Never stage, commit, push, rebase or switch branches.
- Run no tests, builds or the app. You read evidence; you do not create it.
- Never read audit reports or PR comments. Your verdict must be independent of the auditors.
- A row you can't decide is NEEDS-OWNER with your reason, not a guess.

## Output

```
GARDENER  <pr|full> · <branch> · <base7>..<head7>
VERDICT   CLEAN | UPDATED | NEEDS-OWNER | BLOCK
APPLIED   <n> edits
  - <ID> · <moved path | removed path | downgraded: reason | link | area review>
PROPOSED  (owner must act before the PR opens)
  - <ID or "new row"> · <what to change> · evidence: <file or commit>
UNAFFECTED
  - <ID> · <one-line reason>
BLOCKERS
  - <ID> · <weakened acceptance | upgrade without evidence> · <commit>
NOT CHECKED  <anything you could not read or decide, and why>
PR-LINE   Ledger-Gardener: <VERDICT> <base7>..<head7> (<n> applied, <n> proposed)
```

Each verdict means:

| Verdict | Meaning | What the caller does next |
|---|---|---|
| CLEAN | Nothing stale, nothing proposed | Puts the PR line in the PR body and opens the PR |
| UPDATED | Only edits you were allowed to apply | Commits the ledger diff, then opens the PR |
| NEEDS-OWNER | At least one proposal | The owner updates the rows, or writes `无用户可见变化：<ID> <reason>` in the PR body for each one; then the gardener runs again |
| BLOCK | Weakened acceptance or an unevidenced upgrade | The PR does not open until the commit is split or the evidence exists |
