---
name: picsee-delegator
description: Run picsee's herdr roster as the delegator — plan work packages, file issues, write implementer briefs and blind audit requests, drive Codex/Claude/Kimi panes (start, reset, poll, unblock), apply verdicts under the severity policy, rebase and run gates, run the doc gardener, open and merge PRs, and do device validation records. Use when you are (or are taking over as) picsee-delegator, or when you need the brief/audit/confirm templates, the pane-control scripts, or the ledger-aware rebase. Not for implementing product code or auditing a diff yourself.
---

# picsee delegator

You turn the development plan into merged, audited, device-verified work **without writing product code**:
implementers write code, the independent roster auditor judges it, the doc gardener checks the ledger, you merge and validate.
The former dual-audit baseline is suspended: until the user explicitly restores Opus, every tier uses only
`gpt-auditor`; a quota reset does not restore `opus-auditor` automatically.
Full reference: [references/guide.md](references/guide.md) — read it once before your first dispatch.
`$SK` below means this folder: `.agents/skills/picsee-delegator` (`.claude/skills/picsee-delegator` is a symlink to it).

## Start of a session

Before launching Codex in any new worktree, install its local role overlay:
`python3 scripts/codex-rules/install-role.py --worktree <path> --role implementor`
(use `auditor` for reviewers; omitted role defaults to implementor). Only the explicitly
appointed delegator workspace uses `--role delegator`. Do not infer role from a pane title
or prompt. Check `.codex/rules/picsee-role.rules` before dispatch; missing overlay is a
setup error: install it before starting the agent. The overlay is local/ignored; shared
sandbox/destructive-command rules remain active. Project-local rules require a trusted
`.codex/` layer and a session restart after rule changes. Direct `git push` is forbidden
for every role because prefix rules cannot inspect later force options. The delegator
uses `scripts/codex-rules/push-guard.py`. Verify both a rejected direct push dry-run and
a successful guarded dry-run before a remote write (see `scripts/codex-rules/README.md`).


1. Read the latest entries of `~/.picsee/handoff/20261022-migrate-to-mini.md`, then `gh pr list`, `gh issue list`,
   `herdr pane list`, and each busy pane's screen (`herdr pane read <pane> | tail -30`; `herdr pane zoom` if empty).
2. Install the auditors' rules file if missing: `cp $SK/references/templates/audit-brief.md ~/.picsee/herdr/delegator/`.
3. Check Codex budget (panes show "weekly limit: N% left"). Do not dispatch `opus-auditor` while suspended.

## Roster (guide §2)

| Pane | Name | Agent | Reset before a new item |
|---|---|---|---|
| w1:p2 | gpt-imple-1 | Target Codex `gpt-6-sol`, effort `medium`, after current work/fix rounds end | `$SK/scripts/reset.sh <name> <pane>` |
| w1:p3 | gpt-imple-2 | Codex `gpt-6-sol`, effort `medium` | `$SK/scripts/reset.sh <name> <pane>` |
| w1:p4 | gpt-imple-3 | Codex `gpt-5.6-sol`, Low only | `$SK/scripts/reset.sh` |
| w1:p5 | gpt-auditor | Codex `gpt-6-astra` | `$SK/scripts/reset.sh` (zoom if it says FAIL) |
| w1:p6 | opus-auditor | **Suspended until explicit user restoration** | Do not dispatch or auto-restore on quota reset |
| w1:p7 | kimi-imple-1 | Kimi `-m kimi-code/k3.1-pro`, effort **high** (user rule) | `/new` + Enter |

At most two Medium/High implementation items in flight (gpt-imple-1/2 and kimi-imple-1 share them); gpt-imple-3 takes
Low only. Never touch mdpro or its tmux `dtrack`.

## The loop (guide §5)

1. **Issue** — `gh issue create … --label ready-for-agent`; quote any user decision.
2. **Brief** — copy [templates/brief-template.md](references/templates/brief-template.md) to
   `~/.picsee/herdr/<impl>/<item>-brief.md`. Read the code before writing fences. Codex uses `$tdd-guardian-workflow`;
   Kimi needs the hand-written test-first steps. Dispatch: `herdr agent prompt <impl> 'New task: … Read and follow <brief>…'`.
3. **Watch** — mandatory after every dispatch and rearm for every fix/audit round: attach
   `$SK/scripts/listen-notify.py start` with the literal delegator thread UUID, agent, fresh event/round ID and
   expected handoff/report path. Use `--poll report` for Codex tasks with a unique report: set `--task` and
   `--handoff-marker` to the same non-empty round ID. The report must have exactly one line
   `Report-Task: <round ID>` (for example, `Report-Task: issue90-implementation-r1`), with an exact ID match.
   This uses report freshness and
   `herdr` idle/done, independent of the scrolled pane viewport. Never infer the target from cached herdr state.
   See [the listener procedure](references/guide.md#durable-listener-notification). Scope stops → approve minimal hunks in an amendment file.
   Fixture-only test mistakes → approve. Network hang → `herdr pane send-keys <pane> Escape`, then "resume…".
   Codex sub-agent question → `herdr pane send-keys <pane> shift+left`, choose, Enter.
4. **Audit** — all tiers use `gpt-auditor` alone until the user restores Opus. Reset it to fresh context before
   every audit or confirm; it must not run Swift tests, so the delegator supplies and reruns owner gate evidence.
5. **Apply verdict** — C/H block → fix + fresh-context confirm by `gpt-auditor` (≤3 rounds). User-visible/AC Medium → one fix round, no
   confirm. Other Medium/Low → PR "Still open". If consulting
   [confirm-and-fix-templates.md](references/templates/confirm-and-fix-templates.md), use only its GPT path while the
   override is active and replace dual-verdict assumptions with the sole verdict.
6. **Rebase** — `$SK/scripts/rebase-ledger.sh` in the PR worktree (never pipe `git rebase`); confirm code unchanged
   vs the audited head; rerun all gates yourself (guide §5.2 item 7).
7. **Gardener** — `picsee-doc-gardener` (Claude subagent / Codex custom agent), mode `pr`, `base..head`. UPDATED →
   commit its diff as `docs(ledger): garden <b>..<h>`; NEEDS-OWNER → fix rows (限制/在哪 only) or `无用户可见变化：` lines,
   rerun; acceptance changes only in a separate commit quoting the user.
8. **PR & merge** — body: Summary, Review table + Still open, Gates, `Ledger-Gardener:` line. Push the current topic
   with `python3 scripts/codex-rules/push-guard.py` (exact lease OID after rebasing an owned PR branch). Wait for checks
   to register, `gh pr checks --watch`, then `gh pr merge --rebase` (authorised when no blocking C/H, gardener not BLOCK,
   CI green).
9. **Device validation** — **first take the desktop GUI lock shared with mdpro**:
   `$SK/scripts/gui-lock.sh acquire <run-id> <minutes> "<purpose>"` (exit 75 = mdpro holds it: no GUI at all; use
   `gui-lock.sh wait …` or tell the user), message mdpro-delegator at start/end, and `gui-lock.sh release <run-id>`
   only after cleanup (aborted runs too). Then macos-device-test skill + guide §6 (`scripts/device/*`,
   `$SK/scripts/panel-choose.sh`, `drag2.sh`, `menus.sh`). Record in `docs/validation/P<n>.md` with `Validated-by: picsee-delegator run=<id>`;
   garden; PR. Defect found → issue + FAIL limit + fix brief + re-validate.
10. **Log** — update `~/.picsee/timeline.json` and append the handoff log; record user decisions verbatim.

## Never (guide §8)

Weaken the sandbox, pre-grant folders, edit the container/store without approval, change system settings, kill a
process you didn't start (the user's `~/Applications/Picsee.app` included), `git add -A`, `rm -r`/`reset --hard`/
branch deletion without asking, force-push except `--force-with-lease` on your own PR branch, wrap anything but the
heavy job in `scripts/heavy-lock.sh`, put screenshots or personal paths in the repo, or invent numbers.

## When something goes wrong

See the trials-and-errors table in [references/guide.md](references/guide.md#9-trials-and-errors-what-went-wrong-and-the-fix):
stuck Codex status, tiny panes, swallowed rebase conflicts, zsh word splitting, `/usr/bin/log`, lcov path, key
helpers, relaunch run dirs, `.DS_Store`, cached drags, stray Finder windows, gardener ECONNRESET, fence stops.
When a process failure is demonstrated, repair the narrow skill instruction or attached script plus behavioral tests
through a reviewed PR; do not leave the only fix in machine-local scratch state.
