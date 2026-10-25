# Delegator guide (picsee herdr roster) — full reference

This is the long reference behind `SKILL.md`. Paths to helpers are under `.agents/skills/picsee-delegator/scripts/`.

For the agent that takes over **picsee-delegator**: Claude Code, Codex or anything else that can run a shell. It
describes how the roster has actually been run on the Mac mini since 2026-10-22. AGENTS.md, the feature ledger,
`docs/agents/doc-gardening.md`, `docs/agents/audit-dimensions.md` and the roster plan
(`docs/plans/20261021-herdr-roster-migration-plan.md`) stay authoritative. Where this guide disagrees with them,
they win and this guide needs fixing.

Paths outside the repo are written with `~`. Machine-local state (briefs, reports, run evidence) lives under
`~/.picsee/` and is **never committed**.

---

## 1. The role in one page

The delegator turns the development plan into merged, audited, device-verified work. It **does not write product
code**. Code goes to implementers, verdicts come from auditors, and the ledger is checked by the doc gardener.
The delegator itself:

1. Plans the next work packages (WPs) and files GitHub issues (`gh issue create`).
2. Writes the **brief** for an implementer, dispatches it and answers scope questions.
3. Writes **audit requests** and dispatches the independent roster auditor with fresh context.
4. Writes fix briefs and decides between a confirm round and Still open.
5. Rebases, reruns the gates itself, runs the **doc gardener**, opens the PR and merges it with
   `gh pr merge --rebase` once CI is green.
6. Runs **device validation** on the mini (the macos-device-test skill), writes the record in
   `docs/validation/P*.md`, gardens it and merges it.
7. Keeps the user informed, asks for decisions only when they are genuinely the user's, and records every user
   decision verbatim (commit body, roster plan, handoff log).

Merge authority, granted by the user: merge without asking when the active audit shows no blocking Critical/High, the
gardener is not BLOCK, and CI is green.

---

## 2. Machine, session and roster

- Mac mini (M4, 16 GiB, macOS 26.4, 1920×1080 **@1x**), Xcode 26.6 (17F113) at `/Applications/Xcode.app`.
- **Repo:** main checkout `~/Documents/mac-app/picsee`, plus one worktree per pane under `~/Documents/mac-app/picsee-wt/`.
- **Terminal multiplexer:** [herdr](#3-herdr-cheat-sheet), session `picsee`, workspace `w1`. Pane IDs are stable
  (`w1:p1` …) until a pane is closed.
- The mdpro project shares the machine (tmux `dtrack`, its own delegator). **Never touch mdpro**: never drive its
  tmux beyond what the remote-ssh skill allows, and never edit its files. Coordinate with mdpro-delegator only
  about the shared heavy lock.

| Pane | Name | Agent / model | Worktree | Role |
|---|---|---|---|---|
| w1:p1 | picsee-delegator | Claude Code, Opus (or you) | main checkout | delegator |
| w1:p2 | gpt-imple-1 | Target Codex `gpt-6-sol`, effort `medium`, after its current work/fix rounds end | `picsee-wt/gpt-imple-1` | Medium/High implementer |
| w1:p3 | gpt-imple-2 | Codex `gpt-6-sol`, effort `medium` (transition applied) | `picsee-wt/gpt-imple-2` | Medium/High implementer |
| w1:p4 | gpt-imple-3 | Codex `gpt-5.6-sol` | `picsee-wt/gpt-imple-3` | Low-only implementer |
| w1:p5 | gpt-auditor | Codex `gpt-6-astra`, reasoning high — **paused since 2026-10-25** | `picsee-wt/gpt-auditor` (detached) | do not dispatch or auto-restore |
| w1:p6 | opus-auditor | Claude Code, `--agent picsee-opus-auditor --model opus` | `picsee-wt/opus-auditor` (detached) | sole auditor |
| w1:p7 | kimi-imple-1 | Kimi Code CLI, **K3.1 Pro, thinking effort high** (user rule) | `picsee-wt/kimi-imple-1` | Medium/High implementer |

**Slots:** at most two Medium/High implementation items in flight at once. gpt-imple-1/2 and kimi-imple-1 share
them. A third slot is for gpt-imple-3's Low items only.

**Panes that are too small.** p3 and p5 are often 2–3 rows tall, which leaves `herdr pane read` empty and makes
`reset.sh` report `FAIL … after /new` falsely. Run `herdr pane zoom <pane>` to resize, then read again.

---

## 3. herdr cheat sheet

```sh
herdr pane list                               # all panes, agent kind, status, cwd
herdr pane read w1:p3 | tail -30              # visible screen
herdr pane zoom w1:p3                         # toggle zoom (fixes tiny panes)
herdr pane send-text w1:p6 '/clear'           # type text…
herdr pane send-keys w1:p6 Enter              # …and submit it (send-text alone does not submit)
herdr pane send-keys w1:p3 Escape             # interrupt a Codex turn (context is kept)
herdr pane send-keys w1:p3 shift+left         # open a pending Codex sub-agent question ("? 1 question ⇧← to answer")
herdr pane split w1:p4 --direction down       # new pane; returns its pane_id
herdr agent start <name> --kind <codex|claude|kimi> --pane <id> -- <agent args>
herdr agent prompt <name> '<text>'            # send a whole prompt to a named agent
herdr agent get <name>                        # JSON incl. agent_status
```

Queueing a follow-up while a Codex agent works: `send-text`, then `send-keys Tab` twice.

### Status is unreliable for Codex

herdr's `agent_status` can be stale for Codex. For a Codex task with a unique report, use the report-aware
listener mode below. It requires both a fresh report with exactly one `Report-Task: <task ID>` line and
`herdr` idle/done; a scrolled
pane showing old activity cannot prevent detection. The older screen poller remains available for tasks without a
report. Run
`.agents/skills/picsee-delegator/scripts/poll-idle.sh <agent> [interval] [max_min]` in the background. It prints
`<agent> idle|question <time>`, using these rules:

- A question screen ("to answer", "enter submit") exits immediately.
- Codex is busy while the screen shows "esc to interrupt", and idle when "Worked for …" appears near the bottom.
  Two idle reads in a row are required.
- An empty screen falls back to herdr status.
- For Claude panes, herdr status is reliable.

For **Kimi** (and Claude panes), herdr status is reliable (`working` → `idle`/`done`). The shipped adapter is
`poll-handoff.sh`; give the listener a unique round marker when the report file is reused.

Don't grep a Kimi screen for words like "permission"; that produced a false "question" once.

### Durable listener notification

Starting a bare poller is not enough: it can finish after the delegator's shell or turn exits and leave only a local
log. Immediately after every implementation, fix, audit or confirm dispatch, start the attached listener. **Choose
the active delegator host explicitly for each new event**; this is independent of the implementer/auditor model and
does not restore the paused `gpt-auditor`.

- **Codex delegator:** use `--route codex-thread --thread '<current CODEX_THREAD_ID>'`. Copy the UUID from the
  current delegator process; if unavailable, verify the active thread against Codex's local session state. Never
  infer it from cached `herdr agent_session`, which has pointed at a stale, wrong session. A legacy `--thread`-only
  event remains a schema-1 Codex route and is neither rewritten nor retargeted.
- **Claude/Opus delegator:** before inspecting the pane, run `$SK/scripts/gui-lock.sh status`. Read a fresh
  `herdr pane list` and copy the delegator pane's `pane_id`, `terminal_id`, and absolute repo `cwd` into
  `--route claude-pane --pane ... --terminal-id ... --cwd ...`. Copy the **literal absolute cwd spelling** from
  herdr, including any symlink alias; registration and preflight compare that spelling exactly. The listener checks
  a fresh pane-list envelope before delivery: exactly one pane must match, report `agent: claude`, and have the same
  terminal ID, `cwd`, and `foreground_cwd`. It writes the full notice to
  `~/.picsee/herdr/delegator/listeners/<event>/notification.txt`, then sends only
  `: PICSEE_LISTENER_EVENT_<event>` through `herdr pane run` (text plus Enter). In a shell, `:` is a no-op and the
  event ID contains no shell metacharacters. It checks pane identity again after an observed herdr success. This
  prevents a changed pane observed by either check from getting a success receipt; it does not bind the send to a
  terminal or session. Do not reuse an old target after a Claude restart.

  **Hold while the user types (#154).** After the identity check, the listener reads
  `herdr pane read <pane> --source visible --format ansi` and sends only when the Claude input box is
  **empty**. The box is the text between the last two full-width `─` rule lines (the top one may end in
  ` <label> ─`); its first line must start with `❯`. Text drawn dim (SGR 2) is Claude's grey prompt suggestion and
  does not count; any other non-blank character in the box, including continuation lines and a
  `[Pasted text …]` placeholder, is **typing**. Dim counts only for SGR encodings the parser recognises in full
  (`;` parameters, 38/48/58 colours in `;` or ITU `:` form, 0/00/22 resets, the neutral attribute and colour
  codes); any other SGR (unknown code, unpaired colour, other colon sub-parameters, private marker,
  intermediate byte) ends dim, so the text after it is **typing**, never empty. No box, a different prompt
  glyph (`!` shell mode, a menu), or a scrolled-up viewport is **unknown** and is held like typing.

  When that read is empty, the listener writes `delivery-uncertain`, reads the box once more (the **gate read**)
  and runs `herdr pane run` straight after it only if the gate read is also empty; otherwise it returns to the
  hold, nothing sent. A failed list or read is a preflight failure (bounded attempts). While held, `status.json`
  is `waiting-user-typing` with `input` (`typing`/`unknown`) and `deferred_seconds`, the real elapsed time on a
  monotonic clock since the box was first seen non-empty, including herdr call time; the listener re-checks
  identity and the box every `--typing-retry-seconds` (default 5, the last sleep capped to the deadline)
  without using a delivery attempt and never sends keys, clears or edits the user's text. After
  `--typing-defer-seconds` (default 900) the state becomes `deferred-user-typing` (`retrying: true`) and the
  worker keeps re-checking at least 60 s apart, or the configured `--typing-retry-seconds` if longer, until
  `--typing-give-up-seconds` (default the larger of 14400 and the defer time); then it records `deferred-user-typing` with `retrying: false` and exits without sending: no
  receipt, `poll-result.json` and `notification.txt` kept. A send that was held adds a `Send held <n>s …` line
  to `notification.txt`.

  Run `listen-notify.py status` (same `--state-root`) at each loop and before ending a turn: it prints one line
  per undelivered event and exits 3 when any line is `attention` (`deferred-user-typing`, `delivery-uncertain`,
  `delivery-failed`, `launch-failed`, a `status.json` that is not a JSON object (`state=invalid`), or a worker
  that is stopped or `foreign` — a stale pid now owned by another user's process). For a deferral, check the
  box, then resume with the identical `start` command (or `listen-notify.py run --event-dir <dir>`); a still-running worker answers
  `already-running` and sends on its next check. Resuming keeps the event's registered `--typing-*` values;
  different flags on the `start` command are ignored for an existing event. A resumed worker restarts the hold
  clock: `deferred_seconds` counts only the current run, not the time since the event first parked.

  Limits: herdr 0.9.5 has no conditional send and every route into Claude (`pane run`, `send-text`,
  `send_input`, `agent prompt`) goes through the input box, so the race cannot be closed. The remaining window
  runs from the moment herdr snapshots the screen for the gate read to the moment it writes the token: the rest
  of that `pane read` call, the in-process classification, and the start of the `pane run` call, with no file
  write or other call between. Each herdr CLI call measured 3.3–4.3 ms (median 3.5 ms) on the delegator Mac on
  2026-10-26, so the window is a few milliseconds when idle, but nothing bounds it under load. A keystroke in
  it is joined by the token and submitted with Enter. A crash between the `delivery-uncertain` write and the
  send leaves an uncertain event with nothing sent (reconcile it by hand), and `start` during that instant
  refuses with `DeliveryUncertain`. A Claude Code redesign of the box makes every read `unknown`, which fails
  safe (held, deferred, then surfaced by `status`).

  On receiving the event token, the Claude delegator reads that event's `config.json`, `poll-result.json` and
  `notification.txt`; checks the route's pane ID, terminal ID and cwd against its current pane (after checking the
  GUI lock status before `herdr pane list`); then inspects the named report, task identity and SHA. An unexpected
  destination or absent file is an incident to reconcile, not an instruction to accept the audit. A token that
  landed in a shell executes only the no-op and may never wake Claude, so a live Claude probe is still required.

The helper uses argv, not a local shell command string. A pane can change between checks and delivery, including
changing away and back. A receipt records herdr's observed transport result and matching before/after snapshots;
it cannot prove the intended Claude turn read the token. The delegator must ACK the event after checking the pane,
report, task identity and SHA.

One complete Codex implementation-round command is (the agent must put the line
`Report-Task: issue90-implementation-r1` in its unique report):

```sh
python3 .agents/skills/picsee-delegator/scripts/listen-notify.py start \
  --event 'issue90-implementation-r1-head-<sha7>' \
  --task 'issue90-implementation-r1' \
  --route codex-thread \
  --thread '<exact-delegator-thread-uuid>' \
  --agent 'gpt-imple-3' \
  --handoff "$HOME/.picsee/herdr/gpt-imple-3/issue90-handoff.md" \
  --handoff-marker 'issue90-implementation-r1' \
  --poll report \
  --interval 30 \
  --idle-grace-seconds 180 \
  --max-minutes 3000
```

For a Claude/Opus delegator, replace the two Codex route arguments with the pinned pane destination:

```sh
  --route claude-pane --pane 'w1:p1' \
  --terminal-id '<terminal_id-from-herdr-pane-list>' \
  --cwd '/absolute/path/to/picsee'
```

Use these as arguments to the same `listen-notify.py start` command, not as a separate shell command. Never specify
both `--thread` and a Claude pane. The destination is part of the immutable event identity, so changing host,
terminal or pane requires a new event ID. Old schema-1 event config and receipts keep their Codex format.

Use `--poll handoff` for Kimi/Claude and add `--handoff-marker '## Fix round 1'` when a report is appended or
reused. `--poll idle` remains available where no unique report can be required. Report mode checks the expected
file's modification time against listener registration and requires exactly one line formatted
`Report-Task: <task ID>`, with the whole ID equal to both non-empty `--task` and `--handoff-marker`.
`Report-Task: issue90-r10` does not identify `issue90-r1`; duplicate identity lines are stale evidence.
It completes only on fresh report plus idle/done. If idle/done persists without a fresh report for the configured
grace period, it queues `missing-handoff` for reconciliation. A blocked status queues immediately. Working with
an old report stays pending until a status change or the bounded deadline. Neither idle nor a report alone means
acceptance. Every dispatch or rearm gets a new `--event` and matching `--task`; include the round and expected head or
other unique token. Reusing an event with a different agent, task, destination, poll argv or report path is rejected.

The start command detaches a new process session, so it survives the parent shell and agent turn. Runtime state is
under `~/.picsee/herdr/delegator/listeners/<event>/`: `config.json`, `pid`, `listener.log`, `status.json`,
`poll-result.json`, and, only after accepted Codex queue or Claude pane delivery, `queue-receipt.json`. Claude events
also retain `notification.txt`; the token points to that event directory. The receipt filename is retained for
compatibility; new receipts identify the selected destination. The shipped pollers
have a listener-enforced overall deadline of `--max-minutes` plus one poll interval and 10 seconds. If a poller
hangs inside `herdr`, the listener terminates its private poller process group, records `timeout` in
`poll-result.json`, and continues to queue a **needs inspection** message. The private group leader remains alive
until cleanup after either a normal poller exit or a deadline, so a poller cannot leave a same-group child running after
its result is recorded; failed cleanup records a poll error for inspection. Codex queue delivery and Claude
preflight use finite 30-second attempts and bounded exponential backoff; a Claude send itself is attempted once.
No heavy lock is taken. A nonzero poller exit, timeout, blocker,
question, `missing-handoff`, or missing/stale report is still queued as **needs inspection** and is never labelled
successful or accepted.

Inspect `status.json` and `poll-result.json` first. For Claude, this installed herdr version was observed to return
exit 0 with **empty stdout/stderr** after `pane run` delivered text plus Enter to a scratch shell pane; missing pane
returned exit 1 with JSON error. The listener accepts only that observed success shape and requires the post-send
pane check. Any timeout, nonempty unknown success, error or post-send identity change is `delivery-uncertain` with
no receipt. It is never automatically replayed: inspect the pane and event, then use a new event ID only after
manual reconciliation. Preflight failures happen before any send and may retry within the configured bound;
`deferred-user-typing` is also a no-send state and may be resumed.

A `queue-receipt.json` proves only transport acceptance under those limits; it is
not the delegator's ACK and poll completion is not audit acceptance. Before relying on a new host or environment,
run one user-authorized probe event, confirm the exact Codex thread or Claude pane visibly receives it, ACK it there,
and then continue the real work. Do not make the helper accept an audit, merge, or advance a lifecycle unattended.

Failed Codex delivery keeps the poll result and can be retried with the identical command; repeats after a receipt
do not queue again. Claude retries only failures before `pane run`; it persists `delivery-uncertain` **before**
entering the send so even a crash before receipt blocks replay of that event. Registration and delivery are
serialized per event without holding a duplicate lock through the long poll. Codex still has an at-least-once edge
if its queue accepts input but the listener crashes before its receipt. A Claude send may have succeeded even when
no receipt exists; do not treat the absence as permission to resend. Event IDs and message labels support manual
deduplication, not exactly-once transport.

This helper is available after its reviewed change lands; it does not migrate or stop listeners already running, and
it does not provide unattended acceptance or merge safeguards. When a real operating failure is demonstrated, fix
the narrow instruction or attachment and add a reproducing behavioral test in a reviewed PR instead of keeping the
repair only under `~/.picsee/`.

---

## 4. Starting and resetting agents (fresh context per item)

Every new work item starts in a **fresh conversation**. Fix rounds for the same item may continue in the same
conversation, but reset it if its context is above ~80%; the fix brief must then list what to read first.

| Agent | Reset | Notes |
|---|---|---|
| Codex (p2–p5) | `.agents/skills/picsee-delegator/scripts/reset.sh <name> <pane>` | Sends `/new`, then Enter twice (the "Where should the new conversation run?" chooser). Then check `Context 0% used` on screen. Zoom first if the pane is tiny. If the next prompt "didn't land" (still 0% and idle after 20 s), send it again. |
| opus-auditor (p6) | `herdr pane send-text w1:p6 '/clear'` + `send-keys Enter`; the footer must show `Context 0%` | Start: `herdr agent start opus-auditor --kind claude --pane w1:p6 -- --agent picsee-opus-auditor --model opus --dangerously-skip-permissions`. `/clear` does not reload the agent file: after a change to it lands, move `picsee-wt/opus-auditor` to the new main and restart the pane. Network drops show `ECONNRESET` retries; if a turn ends "Interrupted", prompt it to resume the same request. |
| gpt-auditor (p5) | No requests while paused | Only an explicit user restoration reactivates it; a Codex quota reset does not. |
| kimi-imple-1 (p7) | type `/new`, Enter; the status bar must show `context: 0%` | Start: `herdr agent start kimi-imple-1 --kind kimi --pane w1:p7 -- --yolo -m kimi-code/k3.1-pro`. Effort comes from `~/.kimi-code/config.toml` (`[models."kimi-code/k3.1-pro"] default_effort = "high"`). The status bar must read `K3.1 Pro thinking: high`. The first run in a new folder asks "Trust this folder?". Kimi lives in `~/.kimi-code/bin`, which `.zshrc` puts on PATH; a non-login shell may not find `kimi`. |

To create a **new implementer pane**:

1. `git worktree add -b <branch> ~/Documents/mac-app/picsee-wt/<name> origin/main`
2. `herdr pane split …`, then `send-text 'cd <worktree>'` + Enter.
3. `herdr agent start <name> --kind … --pane … -- <args>`.
4. Give it a small Low trial task first. Audit it with the active independent auditor and evaluate the agent before
   you trust it with Medium work. Kimi's historical admission used opus-auditor; that is not an active routing rule.

---

## 5. Work item lifecycle

```
plan → issue → brief → dispatch → (scope questions / amendments) → handoff
  → blind audit → verdict → fix round (± confirm) → rebase → gates → gardener
  → UI parity capture + independent review (if UI changes) → PR → CI → merge
  → full feature validation → validation record PR → timeline / handoff log
```

Risk tier decides the audits:

| Tier | Typical scope | Audit |
|---|---|---|
| Low | docs, ledger wording, mechanical renames, tiny scripts, Low audit follow-ups | opus-auditor alone, one blind round; apply the shared severity policy in §5.5 to every finding |
| Medium | ordinary features, UI states, navigation, scanning | opus-auditor alone; one fix round for user-visible/AC Mediums, no confirm |
| High | FileAccess/sandbox/bookmarks, entitlements, concurrency core, anything that can lose data or access | opus-auditor alone; every C/H gets a fresh-context confirm; at most 2 auditor rounds, then the user decides |

Raise the tier if a change touches FileAccess, AccessIntent, the loader, entitlements, Info.plist or signing.
This Opus-only table is an active user override (2026-10-25: 「Opus单审，gpt暂停」). It replaced the 2026-10-24 GPT-only override
(「目前opus auditor qouta 不够用了，暂时停用opus-auditor，只由gpt-auditor 来审」). The dual-audit baseline stays suspended
and gpt-auditor stays paused until the user explicitly restores it; never infer restoration from quota availability.

### 5.1 Issue

`gh issue create --title "<WP>: <summary> (<ledger IDs>)" --body-file … --label ready-for-agent`. The body says
what happens today (with evidence), what is wanted, constraints, ledger IDs and tier. For a user decision, quote
the user's words.

### 5.2 Brief (implementer task document)

Put it at `~/.picsee/herdr/<implementer>/<item>-brief.md`. Templates that worked:
`~/.picsee/herdr/delegator/p1-brief-P1-02.md`, `p2-brief-P2-01.md`, `p2-brief-P2-02.md` (long, for Codex) and
`~/.picsee/herdr/kimi-imple-1/issue82-brief.md` (short, for Kimi). A brief contains:

For any UI change, complete the state mapping, pinned design source, native exceptions, and evidence plan in
[`docs/agents/ui-parity-contract.md`](../../../../docs/agents/ui-parity-contract.md) before dispatch. Apply its
signed-device comparison and independent review **before merging the UI PR**. Uncaptured required states are
`NOT VERIFIED` and block merge; name unreachable future-work states `PENDING` with their work package.

1. **Header:** who they are, worktree, exact branch command (`git fetch origin && git switch -c <branch>
   origin/main`), base SHA, issue number, tier and why.
2. **Read first:** `AGENTS.md` (Codex loads it by itself; Kimi does not reliably do so, so tell it explicitly), the
   ledger rows, the plan section, ADRs, relevant validation records.
3. **WI-0, "probe the risky seam first"**, when a High/Medium change rests on an assumption only the device can show
   (for example, can a dragged URL be leased?). Say exactly what to do when the probe can't be run, and when to stop.
4. **Acceptance criteria AC-n,** each tied to ledger rows and testable.
5. **Ownership fences:** "You own, and may edit" and "Not yours". Read the code before you write fences. P1-02 stopped
   twice because the fences left no room for a needed hook. Name shared files and split hunks when two
   implementers run in parallel (see the P2-01/P2-02 briefs). Say "if you need a fenced file, stop and ask".
6. **Test-first process:**
   - Codex: `$tdd-guardian-workflow` (plan → design tests with spec adversary → implement per WI with RED receipts →
     coverage), RED receipt IDs per WI.
   - Kimi (no plugin): "write the tests first, run only them, paste the failing assertion output (not compile errors)
     into the handoff, implement, rerun the same filter, paste GREEN".
7. **Gates** (copy verbatim):
   ```sh
   export PATH=$HOME/.picsee/tools/xcodegen/bin:/opt/homebrew/bin:$PATH DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   scripts/heavy-lock.sh swift test --package-path Packages/PicseeKit --enable-code-coverage
   sh scripts/tdd/swift-lcov.sh      # writes coverage/lcov.info; sum LF/LH, FNF/FNH → must be 100% lines and functions
   xcodegen generate
   scripts/heavy-lock.sh xcodebuild build -scheme Picsee -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath .build/dd-ci
   node --test --test-reporter=spec scripts/tdd/*.test.mjs scripts/ledger/*.test.mjs
   node scripts/ledger/build.mjs --check
   ```
8. **Ledger rules:**
   - Only the text after 「限制：」 may change in a behaviour commit.
   - Never raise a row above Partial without a device record.
   - Commit md and html together (`node scripts/ledger/build.mjs`).
   - Never change an acceptance sentence; that is the delegator's separate commit quoting the user.
9. **Commits:** `<type>(<scope>): …`; the body names issue, WP and ledger IDs; trailer `Implemented-by: <name>`;
   stage named paths only; no push, PR, branch deletion, `rm -r`, or touching other worktrees.
10. **Device smoke** (implementer smoke is not validation): `pgrep -x Picsee` first. Never kill a Picsee it didn't
    start. The user's `~/Applications/Picsee.app` is off limits. No pre-granting, no container edits, no system
    settings.
11. **Handoff** at `~/.picsee/herdr/<implementer>/<item>-handoff.md`: design, AC table with the test that proves
    each AC, RED/GREEN or receipts, changed existing assertions (before, after, why), gates output, diff stat,
    production line count, open questions, NOT VERIFIED list.
12. **Open questions with defaults,** plus a closing line: "follow each default; if WI-0 or the code contradicts one,
    stop and report".

Dispatch with a one-line prompt that points at the file, for example `herdr agent prompt gpt-imple-2 'New task: … Read
and follow ~/.picsee/herdr/gpt-imple-2/<brief>.md … Do not push.'`, then start a fresh listener event as described
in [Durable listener notification](#durable-listener-notification).

### 5.3 During implementation

- **Scope stops.** The implementer stops at a fence and proposes a minimal change. If it is reasonable, approve it
  in a file such as `~/.picsee/herdr/<impl>/<item>-scope-amendment-<n>.md` (append later amendments), prompt
  "approved, see file", and list it in the audit request.
- **tdd-guardian "FAILED-VERIFICATION, stop with evidence"** is usually a test-fixture mistake (wrong router
  constructor, `/private/var` vs `/var`). Approve the fixture-only fix if no assertion changes. Grant a standing
  allowance for fixture-only stops, disclosed in the handoff.
- **Codex sub-agent questions** block the turn: open them with `shift+left`, pick an option, press Enter.
- **Network stalls** ("Reconnecting… waiting for network" for many minutes): check with `curl -s -o /dev/null -w
  '%{http_code}' https://api.openai.com/v1/models` (401 means reachable). Then `send-keys Escape` and prompt "resume
  where you left off", listing the commits made so far.

### 5.4 Audit requests

Put each request at `~/.picsee/herdr/delegator/opus-<item>-audit-r<round>.md` and its report at
`~/.picsee/herdr/opus-auditor/opus-<item>-audit-r<round>.md` (exactly one `Report-Task:` line), ending with the VERDICT
block. `/clear` opus-auditor before every audit and confirm. Do not dispatch gpt-auditor until the user restores it.

**opus-auditor runs no builds or tests unless the request asks for a lane re-run** (its agent file). Tell it which owner
gate logs to judge; the delegator reruns applicable gates; no absent second auditor is implied.

Every request carries:
- item, exact range `base..head`, worktree, commit list, and the note "objects are shared; use git show/diff";
- tier with the reason and the raise-the-tier triggers;
- dimensions D1–D12 and the pointer to `~/.picsee/herdr/delegator/audit-brief.md` (blind, read-only, no gh, scratch
  isolation);
- inputs: brief, amendments, handoff ("a claim to test"), evidence dir, receipts command;
- "Judge specifically", 5–10 bullets on the risky points;
- for a new implementer, ask the auditor for an "Implementer assessment" paragraph.

Dispatch only opus-auditor. Its round-one request is blind to previous audit conclusions. For a C/H confirm, reset it
again so the confirmation begins in fresh context, then provide the earlier finding, merged/sole verdict, fix range,
and counter-proof inputs required to judge closure.

**Confirm requests** (`opus-<item>-confirm-r<n>.md`; template `p2-02-confirm-gpt.md`) list each finding in scope
with its requested fix, the fix diff range, any rebase, and "Still open (do not re-judge)". They ask for
CLOSED/PARTIAL/OPEN per finding plus any new C/H.

**Challenge mode is unavailable** under the sole-auditor override. Resolve doubtful C/H with counter-proof or a fix,
then use the required fresh-context opus-auditor confirm.

### 5.5 Applying the verdict and severity policy

- **Critical/High** blocks. Fix round, then a fresh-context confirm from opus-auditor. At most **2 auditor rounds** per
  item: round 1 is the blind audit, round 2 the confirm. If any Critical/High is still open (or newly raised) after
  round 2, do not brief another fix or confirm: report the open findings, their traces and the options to the user, who
  decides whether to continue (user decision 2026-10-25: 「opus auditor 最多2个round，之后如果还有critical/high，交给user来抉择是否继续」).
- **Medium** that is user-visible or breaks an AC: one fix round, no confirm. Other Mediums go to the PR's
  "Still open" and the next Low batch.
- **Low:** fold in only the cheap, obvious ones; the rest go to Still open.

### 5.6 Rebase onto main

Never pipe `git rebase`; check its exit status. Write logs to `$(git rev-parse --git-dir)/rb.log`.

`.agents/skills/picsee-delegator/scripts/rebase-ledger.sh [origin/main]` (run inside the PR worktree) automates the two ledger cases below and stops, leaving the rebase in progress, on anything else.

- **Only `docs/feature-ledger.html` conflicts.** Regenerate and continue, in a loop:
  `node scripts/ledger/build.mjs && git add docs/feature-ledger.html && GIT_EDITOR=true git rebase --continue`.
- **`docs/feature-ledger.md` row conflicts.** `.agents/skills/picsee-delegator/scripts/resolve_rows.py` does a three-way merge
  by row key (stage 1/2/3). It keeps main's text and appends the commit's added suffix. It stops on rows that need
  manual merging, for example when both sides rewrote the same 限制 clause; merge those by hand.
- **Part 3 area-review conflicts.** Use `.agents/skills/picsee-delegator/scripts/resolve_part3.py <file>`: 分发 keeps HEAD, other rows take theirs.
- **Any other conflict** (Swift, `CanvasWindowController`, xcstrings): stop and resolve deliberately, or send it back
  to the implementer.
- After a rebase, confirm the code is unchanged versus the audited head (`git diff --stat <audited> HEAD -- App
  Packages`), then rerun all gates yourself.
- **Rebased PR push:** direct `git push` is blocked. On your own unmerged PR branch, obtain the full current remote
  tip OID and run `python3 scripts/codex-rules/push-guard.py --expected-remote-oid <oid>`. The script uses an exact
  lease and refuses `main`. Ordinary topic pushes use the same script without a lease.

### 5.7 Doc gardener

Run it before opening a PR and before every push of a new head:
- **Claude:** the `picsee-doc-gardener` subagent. It runs on Haiku (`model: haiku` in its agent file; user decision
  2026-10-25: 「picsee-doc-gardener will be powered by Haiku model, from now on」); do not override the model when
  dispatching it.
- **Codex:** the custom agent of the same name.

Pass it the mode `pr`, the worktree, `base..head`, a context paragraph and the handoff path. It edits only Part 3
area-review rows and cautious fixes, and never commits.

| Verdict | Action |
|---|---|
| CLEAN | Put its `Ledger-Gardener:` line in the PR body. |
| UPDATED | Review its diff, commit as `docs(ledger): garden <base7>..<head7>`, open the PR with its line. |
| NEEDS-OWNER | Fix the named rows (only 限制/在哪), or write `无用户可见变化：<ID> <理由>` lines in the PR body for pre-existing problems. Commit, then rerun the gardener. |
| BLOCK | Don't open the PR. Split acceptance changes into their own commit quoting the user, or add device evidence. |

Typical NEEDS-OWNER causes:
- a 怎么确认 cell over ~150 visible chars or 3 sentences;
- an over-claim, such as "@1x passed" for something only `open -a` drove, or "move" when it was a rename;
- a dropped caution that is still true;
- a missing `在哪` path;
- an unlinked smoke claim, since implementer smoke has no record;
- a declared name (entitlement, command) that disappeared from every row.

**Acceptance changes** (the text before 「限制：」) need the user's decision, quoted verbatim, in a separate
`docs(ledger)` commit. Do the same for plan text the decision invalidates (§10 metrics, WP lines).

### 5.8 PR and merge

PR body sections:
- **Summary**, what and why;
- **Review**, the opus-auditor rounds plus a Still open list; do not claim dual review while gpt-auditor is paused;
- **Gates**, with numbers;
- the `无用户可见变化` lines;
- the exact `Ledger-Gardener:` line;
- the attribution line.

For a UI PR, include the contract's `UI-Parity` table for each changed reachable state: pinned Prototype file and
hashes, viewport/appearance/scale, signed App build SHA and run ID, independent verifier and opus-auditor report,
verdict and remaining limits. The independent verifier captures raw App and HTTP HTML images before merge; the
auditor reviews those exact images and input hashes. All required conditions must be `PASS` on the current PR head
(or have a proved App/design/input-identical documentation-only successor). A `FAIL` or `NOT VERIFIED` required
condition means keep the PR draft and fix or capture it; CI and static code review do not clear it. Do not apply
`PENDING` to a reachable state. Other prototype states remain separately tracked, including #92.

Then wait for CI and merge:

```sh
for i in $(seq 1 20); do [ "$(gh pr checks $P | wc -l)" -gt 0 ] && break; sleep 15; done   # checks may not register at once
gh pr checks $P --watch --interval 30; gh pr merge $P --rebase; git pull --ff-only origin main
```

---

## 6. Device validation (macos-device-test)

The validation role belongs to someone other than the implementer; the delegator has been doing it. Read
`.agents/skills/macos-device-test/SKILL.md` and `features/*.md`. Device runs happen only on the mini.

### Desktop GUI lock (shared with mdpro — agreed 2026-10-24)

The mini has one desktop, and mdpro's device tester drives it too. Two drivers at once steal focus, send keys to the
wrong app and corrupt each other's screenshots. A picsee run once overlapped mdpro's batch B6b because picsee didn't
know about the lock. Both projects use mdpro's ADR-0134 decision 6 lock:

- **The lock:** the directory `~/.cache/desktop-gui.lock/` (`mkdir` acquires it) holds an `owner` file of key=value
  lines, and that file is the one that counts. picsee writes `project=picsee`, `session`, `batch=<run-id>`, `start`,
  `pid`, `expected_minutes` and `purpose`.
- **When to take it:** before the **first GUI-driving action** of a run: launching the app, panels, keystrokes,
  mouse, drags, `screencapture`, app activation. Keep it across relaunch sub-runs.
- **When to release it:** only after the app has quit (after `cleanup.sh`), including aborted runs. Builds, log
  reads and shell work don't need it; builds use the heavy lock.
- **Helper:** `.agents/skills/picsee-delegator/scripts/gui-lock.sh acquire|wait|release|status`. It exits 75 when the
  lock is busy, and `release` refuses a lock that isn't picsee's with the same batch.
- **If it's held:** no GUI at all. Poll every 60 s (`wait`). After the holder's `expected_minutes` + 15, stop and
  tell the user. Never remove another project's lock; report a stale-looking lock to the user instead.
- **Courtesy:** message mdpro-delegator (`SendMessage` / cross-session) when a run starts and ends, and check with
  them before each mini GUI run. mdpro does the same.

```sh
RUN_DIR="$HOME/.picsee/device-runs/$(date +%Y%m%d-%H%M%S)-<ledger-ids>"
scripts/device/build.sh "$RUN_DIR"          # signed Debug of HEAD; refuses dirty or untracked inputs
scripts/device/launch.sh "$RUN_DIR"         # records PID, executable, birth time
scripts/device/doctor.sh "$RUN_DIR" --expected-sha <sha7>   # 12 lines must PASS before driving
…drive…
/usr/bin/log show --start "$(cat $RUN_DIR/start.txt)" --style compact --predicate 'subsystem == "io.github.anzchy.picsee"' > $RUN_DIR/app.log
scripts/device/cleanup.sh "$RUN_DIR"        # kills only the recorded PID
```

Driving tools (all synthetic input, which must be disclosed in the record):
- `scripts/device/kc.sh RUN KEYCODE [command shift …]` for named keys: Return 36, Esc 53, Tab 48, ←→ 123/124,
  ⌘O = `31 command`, ⌘W = `13 command`, ⌘Q = `12 command`, ⌘⇧G = `5 command shift`. `key.sh` types exactly one
  printable character and nothing else.
- `.agents/skills/picsee-delegator/scripts/panel-choose.sh RUN PATH`: in an open NSOpenPanel or powerbox, press ⌘⇧G, paste the path
  (⌘A ⌘V through the pasteboard, never `keystroke`, so an input method cannot convert it), then Return twice. It prints
  `input-source: <id>` (read-only) for the record, refuses a pasteboard holding anything but plain text, and restores the
  previous text with a byte compare on every exit except SIGKILL (non-zero if the restore fails or differs). If someone else
  copies while the path is on the pasteboard, it keeps their copy, does not restore, and exits non-zero
  (`pasteboard changed by someone else … not restored`); say so in the run record. The absolute path passes through the
  pasteboard, so clipboard-history tools and Universal Clipboard may record it.
- `.agents/skills/picsee-delegator/scripts/drag2.sh X0 Y0 X1 Y1`: a CGEvent drag from a Finder list-view row with a press-hold. Finder starts a real
  drag session. computer-use drags never arrived.
- `.agents/skills/picsee-delegator/scripts/menus.sh PID` (menu item enabled states), `scripts/axlist.sh PID`, `scripts/click.sh`/`move.sh X Y`, AX clicks via
  `osascript -e 'tell application "System Events" to tell (first process whose unix id is PID) to click …'`.
- Window title via `get name of every window`. Screenshots: `screencapture -x -R480,110,960,640` (window region)
  into `$RUN_DIR/shots/`. Never put screenshots in the repo.

Rules and gotchas:

- **The user's `~/Applications/Picsee.app`** has the same bundle ID and shares the sandbox container, preferences and
  bookmarks with every test build. If it is running, stop and tell the user; never kill it. Finder "Open With" picks
  the registered copy, so Open With can't be validated while it is installed.
- **A relaunch needs a new run directory** (cleanup retires the old one). Create `<RUN>-b-…`, copy `bundle.path` and
  `build.json` into it, then `launch.sh`.
- **Fixtures** are copied from `TestAssets/` with manifest hash checks and written to `fixtures.sha256.json`
  (relative path → sha). Files you will move, delete or drag from Finder go **outside** `fixtures/` (for example
  `folders/`, `drag-src/`), because Finder writes `.DS_Store` and doctor's fixture check fails.
- **Finder `.DS_Store` in the source tree** makes `build.sh` refuse. Move them out of the repo intact to
  `~/.picsee/handoff/ds_store-backup-<ts>/`; never delete them.
- **For drag tests,** use files the app has **never opened**. An earlier `open -a` of the same path gives the process
  access and hides access defects (this masked #73 once). Close stray Finder windows first, or the drop lands in them
  and Finder *moves* the file.
- **Granting folders through the powerbox** writes roots into the shared container. List the root IDs you leave
  behind in the record. Don't edit the store. Moving the store files aside for a cold start needs the user's approval
  each time.
- **Timing-dependent states** (page-24 reading, Cancel Reading, loading/cancel) can't be caught on a local SSD. Record
  them as NOT VERIFIED (timing), never FAIL.
- **NOT VERIFIED (user steps / other machine):**
  - @2x (needs the MacBook);
  - trackpad pinch;
  - a real-mouse drag;
  - VoiceOver;
  - Chinese system UI;
  - System appearance and Reduce Motion;
  - Finder default handler and double-click;
  - memory pressure.

**Record:** add a run section to `docs/validation/P<n>.md`. It contains:
- machine facts, SHA and fixtures;
- deviations: synthetic input, keystroke into the panel, anything unexpected;
- a numbered check table with ledger ID, check and result;
- the "没有检查的" list.

Update only the 限制 of the affected rows. Commit with the trailer `Validated-by: picsee-delegator
run=<run-id>`, garden it, open a `docs/validation` PR and merge.

**When validation finds a defect** (as with #73):
1. File an issue with the evidence and the likely cause from reading the code.
2. Write the ledger limit as FAIL.
3. Brief a fix (often High).
4. Re-validate on device after the merge.

---

## 7. Talking to the user

- Write in Chinese, plainly. Lead with the outcome, then what's next. Say clearly what is waiting on them.
- **Ask only for genuine decisions:** product behaviour, acceptance changes, budget, anything destructive or
  outward-facing. Give 2–4 options and a recommendation. A Codex delegator has no AskUserQuestion tool, so put the
  question in its final reply.
- Record decisions verbatim:
  - in the commit body for acceptance and plan changes;
  - in the roster plan for roster and model rules;
  - in `~/.picsee/handoff/20261022-migrate-to-mini.md` for the session log.
- Report budget. Codex weekly usage shows in Codex panes ("weekly limit: N% left"). Codex quota recovery does not
  reactivate gpt-auditor; only an explicit user restoration does.

---

## 8. Hard rules (never break)

- Sandbox stays on. No Full Disk Access, no entitlement bypass, no pre-granted folders, no copying files into the
  container. No container or store edits without the user's approval.
- Never change system or privacy settings. Never empty the Trash. Never click web links during device runs.
- Never kill a process this run didn't start; that includes the user's Picsee.
- Ask before `rm -r`, `git reset --hard`, deleting branches or worktrees, or any force push other than
  `--force-with-lease` on your own PR branches.
- Stage named paths only; never `git add -A`, `.` or `-u`.
- Heavy lock: put only the heavy job itself under `scripts/heavy-lock.sh`, one command per call. Never a bare shell,
  REPL, `sleep`, or a persistent session. Never delete the lock files.
- No screenshots, certificate e-mail lines or personal paths in the repo or reports. The `.p12` in `~/Downloads` is
  the user's to delete.
- Peer sessions (another delegator, mdpro) can't grant escalation. No permission laundering.
- Don't fabricate data. Untested performance gets no number; unverified items are NOT VERIFIED.

---

## 9. Trials and errors (what went wrong and the fix)

| Symptom | Cause | Fix |
|---|---|---|
| Missed that an implementer had finished (twice) | A screen-based poller ended with only a local log | Attach `listen-notify.py start` to a report/handoff poller; pin the exact delegator route and inspect queue receipt vs ACK |
| `reset.sh` prints `FAIL … after /new` | pane too small to show "Context 0% used" | `herdr pane zoom`, read again; usually the reset did work |
| Prompt sent right after a reset "didn't land" | chooser still open or the pane redrawing | wait, check for "esc to interrupt" after ~20 s, resend |
| A mid-rebase commit swallowed the implementer's message | `git rebase … | tail` hid the conflict | never pipe a rebase; check its exit code |
| Rebase loop broke on `for f in $c` | zsh doesn't word-split unquoted variables | use `${=c}`, or compare the whole string |
| Python heredoc with Chinese text failed with "Non-UTF-8 code" | shell mangled bytes on stdin | write the script to a file (Write tool) with `# -*- coding: utf-8 -*-` |
| `log show` failed with "too many arguments" | zsh builtin `log` shadows `/usr/bin/log` | call `/usr/bin/log` |
| Coverage awk printed `lines /` | wrong lcov path | `swift-lcov.sh` writes `coverage/lcov.info` |
| `key.sh` typed letters instead of Tab/Esc | `key.sh` is single-character only | `kc.sh` with keycodes |
| Open panel path couldn't be typed | `key.sh` is one character | `.agents/skills/picsee-delegator/scripts/panel-choose.sh` (pasteboard paste; disclose it) |
| Open panel showed `…095720-跑01-grid-explore、fixtures、grid` and never navigated (2026-10-25) | `panel-choose.sh` typed the path with `keystroke` under a Chinese IME (Doubao Pinyin) | Fixed in #119: the helper pastes via the pasteboard and restores it; never switch the user's input source |
| `panel-choose.sh` refused: `holds public.png …` | non-text pasteboard contents cannot be restored from text | copy plain text (or ask the user) and rerun |
| `panel-choose.sh` failed: `pasteboard changed by someone else during the run; not restored` | a copy landed while the path was on the pasteboard | nothing to undo (their copy is kept); record it, check the panel went where intended, rerun the step if not |
| `launch.sh` failed in a relaunch dir | missing `bundle.path`/`build.json` | copy both from the first run dir |
| Doctor `window` FAIL at end of run | title is a non-fixture file name | disclose; doctor only knows fixture names |
| Doctor `fixtures` FAIL | files added after hashing, or `.DS_Store` from Finder | hash after copying; keep Finder-touched files outside `fixtures/` |
| `build.sh` refused: untracked `.DS_Store` | Finder browsing in the repo | move them out intact (don't delete) |
| A drag "passed" because of cache | the same path had been opened with `open -a` | drag files the app has never opened |
| A drop landed in another Finder window and *moved* the file | stray Finder window over Picsee | move it back, close stray windows, redo, disclose |
| computer-use drag never arrived | tool limit | `scripts/drag2.sh` CGEvent drag |
| Finder Open With launched the wrong copy | `~/Applications/Picsee.app` registered with the same bundle ID | NOT VERIFIED while the user's copy is installed |
| Gardener died on ECONNRESET | network | check `git status` for partial edits, rerun |
| Gardener NEEDS-OWNER again and again | over-long cells, over-claims, dropped cautions | write limits that state only what the record shows; keep cautions; one fact per clause |
| A brief's target was already fixed (Kimi trial) | brief written from an older audit head | a good implementer reports it and makes no empty commit; check `git log -S` before briefing |
| Implementer stopped at a fence (P1-02 ×2) | fences didn't allow a needed hook | read the code before writing fences; approve minimal amendments in a file |
| A Codex turn hung on "Reconnecting…" for 28 min | network drop | verify network, `Escape`, then "resume, commits so far: …" |
| gpt-auditor reported "no runs" | its sandbox can't take the heavy lock | tell gpt not to run Swift tests; delegator reruns owner gates and supplies evidence |
| Kimi poller false "question" | word match on screen | poll herdr status + handoff file |
| Implementer committed workflow reports into `.claude/tdd-guardian/` | the workflow writes prose there | fix-round item: remove them, keep copies beside the handoff |
| `matchingRoot`-style dead-code briefs | stale finding | check the current main first |

---

## 10. Where state lives

| What | Where |
|---|---|
| Plan, architecture, ADRs, ledger, validation records | repo `docs/` |
| Roster rules (source for `.claude/rules/70-herdr-roster.md`) | `docs/plans/20261021-herdr-roster-migration-plan.md` |
| Session handoff log (append every milestone and decision) | `~/.picsee/handoff/20261022-migrate-to-mini.md` |
| Timeline (WP status) | `~/.picsee/timeline.json` (back it up before editing) |
| Briefs, requests, PR bodies | `~/.picsee/herdr/delegator/`, `~/.picsee/herdr/<agent>/` |
| Audit reports | Active: `~/.picsee/herdr/opus-auditor/opus-<item>-audit-r<n>.md`, `-confirm-r<n>.md`; historical gpt-auditor reports remain evidence but receive no new dispatches |
| Gardener reports | `~/.picsee/gardening/` |
| Device runs (evidence, screenshots, logs) | `~/.picsee/device-runs/<run-id>/` |
| Delegator scripts and templates | `.agents/skills/picsee-delegator/scripts/`, `.agents/skills/picsee-delegator/references/templates/` (`.claude/skills/picsee-delegator` is a symlink to the same folder); the auditors' rules file is installed at `~/.picsee/herdr/delegator/audit-brief.md` (copy of `references/templates/audit-brief.md`) |
| Heavy lock | `scripts/heavy-lock.sh`; flock `~/.picsee/locks/heavy.lock` (never delete) |

A Claude delegator also keeps auto-memory under `~/.claude/projects/-Users-jack-Documents-mac-app-picsee/memory/`. A
Codex delegator doesn't see it, which is one reason this guide and the handoff log exist.

---

## 11. Standing user decisions worth knowing

- **Merge authority and policies:** the delegator merges when there is no blocking C/H, the gardener is not BLOCK
  and CI is green. The Medium policy and C/H confirm rounds are as in §5.5.
- **Implementers:** Codex implementers run with `-s danger-full-access` and use `$tdd-guardian-workflow` (from P1
  wave 3). Kimi is admitted; it always runs K3.1 Pro at effort high (2026-10-24).
- **Auditors:** active override: all tiers use only opus-auditor, `/clear`ed before every audit and C/H confirm.
  User decision 2026-10-25: 「Opus单审，gpt暂停」 (replacing the 2026-10-24 GPT-only override). Do not restore gpt-auditor
  automatically when Codex quota returns; wait for an explicit user restoration.
- **Ledger:** feature-ledger md and html are committed together.
- **Git:** force-with-lease is allowed only on the delegator's own unmerged PR branches.
- **Product decisions of 2026-10-24:**
  - ACCESS-03: a move or rename browses at the new place; reconnect is prompted only when the folder can't be found.
  - A folder opens on its first image by name, after the scan.

When in doubt, read the handoff log's latest entries, `gh pr list`, `gh issue list`, `herdr pane list` and each
pane's screen before acting.

### Live herdr status schema (2026-10-24)

`herdr agent get <name>` returns `result.type = agent_info` and the named agent in
`result.agent`, with `name` and `agent_status`. Report polling validates this envelope
and exact agent name; malformed or mismatched responses become `poll-error`, never completion.
Use sanitized real envelopes in fake-process tests. Before switching a new adapter to live
monitoring, run its status reader against a read-only real `herdr agent get` response;
a flat fake `{agent_status: ...}` is not an integration check. A queue receipt for
`poll-error` means monitoring stopped and needs repair/rearming, not that the task finished.
