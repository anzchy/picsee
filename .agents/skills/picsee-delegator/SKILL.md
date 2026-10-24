---
name: picsee-delegator
description: Run picsee's herdr roster as the delegator — plan work packages, file issues, write implementer briefs and blind audit requests, drive Codex/Claude/Kimi panes (start, reset, poll, unblock), merge verdicts under the severity policy, rebase and run gates, run the doc gardener, open and merge PRs, and do device validation records. Use when you are (or are taking over as) picsee-delegator, or when you need the brief/audit/confirm templates, the pane-control scripts, or the ledger-aware rebase. Not for implementing product code or auditing a diff yourself.
---

# picsee delegator

You turn the development plan into merged, audited, device-verified work **without writing product code**:
implementers write code, two blind auditors judge it, the doc gardener checks the ledger, you merge and validate.
Full reference: [references/guide.md](references/guide.md) — read it once before your first dispatch.
`$SK` below means this folder: `.agents/skills/picsee-delegator` (`.claude/skills/picsee-delegator` is a symlink to it).

## Start of a session

1. Read the latest entries of `~/.picsee/handoff/20261022-migrate-to-mini.md`, then `gh pr list`, `gh issue list`,
   `herdr pane list`, and each busy pane's screen (`herdr pane read <pane> | tail -30`; `herdr pane zoom` if empty).
2. Install the auditors' rules file if missing: `cp $SK/references/templates/audit-brief.md ~/.picsee/herdr/delegator/`.
3. Check budget (Codex panes show "weekly limit: N% left"; the opus-auditor status bar shows Claude weekly usage).

## Roster (guide §2)

| Pane | Name | Agent | Reset before a new item |
|---|---|---|---|
| w1:p2/p3 | gpt-imple-1/2 | Codex `gpt-6.1-sol`, `-s danger-full-access` | `$SK/scripts/reset.sh <name> <pane>` |
| w1:p4 | gpt-imple-3 | Codex `gpt-5.6-sol`, Low only | `$SK/scripts/reset.sh` |
| w1:p5 | gpt-auditor | Codex `gpt-6-astra` | `$SK/scripts/reset.sh` (zoom if it says FAIL) |
| w1:p6 | opus-auditor | Claude `--agent picsee-opus-auditor --model opus` | `/clear` + Enter before every request |
| w1:p7 | kimi-imple-1 | Kimi `-m kimi-code/k3.1-pro`, effort **high** (user rule) | `/new` + Enter |

At most two Medium/High implementation items in flight (gpt-imple-1/2 and kimi-imple-1 share them); gpt-imple-3 takes
Low only. Never touch mdpro or its tmux `dtrack`.

## The loop (guide §5)

1. **Issue** — `gh issue create … --label ready-for-agent`; quote any user decision.
2. **Brief** — copy [templates/brief-template.md](references/templates/brief-template.md) to
   `~/.picsee/herdr/<impl>/<item>-brief.md`. Read the code before writing fences. Codex uses `$tdd-guardian-workflow`;
   Kimi needs the hand-written test-first steps. Dispatch: `herdr agent prompt <impl> 'New task: … Read and follow <brief>…'`.
3. **Watch** — Codex: `$SK/scripts/poll-idle.sh <agent> 120 3000` (background). Kimi/Claude:
   `$SK/scripts/poll-handoff.sh <agent> <handoff.md>`. Scope stops → approve minimal hunks in an amendment file.
   Fixture-only test mistakes → approve. Network hang → `herdr pane send-keys <pane> Escape`, then "resume…".
   Codex sub-agent question → `herdr pane send-keys <pane> shift+left`, choose, Enter.
4. **Audit** — [templates/audit-request-template.md](references/templates/audit-request-template.md); gpt version must
   not run swift test; opus may run it once. Blind, dispatched together. Low → opus alone.
5. **Merge verdicts** — C/H block → fix + confirm by both (≤3 rounds). User-visible/AC Medium → one fix round, no
   confirm. Other Medium/Low → PR "Still open". Templates: [confirm-and-fix-templates.md](references/templates/confirm-and-fix-templates.md).
6. **Rebase** — `$SK/scripts/rebase-ledger.sh` in the PR worktree (never pipe `git rebase`); confirm code unchanged
   vs the audited head; rerun all gates yourself (guide §5.2 item 7).
7. **Gardener** — `picsee-doc-gardener` (Claude subagent / Codex custom agent), mode `pr`, `base..head`. UPDATED →
   commit its diff as `docs(ledger): garden <b>..<h>`; NEEDS-OWNER → fix rows (限制/在哪 only) or `无用户可见变化：` lines,
   rerun; acceptance changes only in a separate commit quoting the user.
8. **PR & merge** — body: Summary, Review table + Still open, Gates, `Ledger-Gardener:` line. Wait for checks to
   register, `gh pr checks --watch`, then `gh pr merge --rebase` (authorised when no blocking C/H, gardener not BLOCK,
   CI green).
9. **Device validation** — macos-device-test skill + guide §6 (`scripts/device/*`, `$SK/scripts/panel-choose.sh`,
   `drag2.sh`, `menus.sh`). Record in `docs/validation/P<n>.md` with `Validated-by: picsee-delegator run=<id>`;
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
