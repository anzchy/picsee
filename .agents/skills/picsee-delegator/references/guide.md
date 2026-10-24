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
| w1:p5 | gpt-auditor | Codex `gpt-6-astra`, reasoning high | `picsee-wt/gpt-auditor` (detached) | auditor |
| w1:p6 | opus-auditor | **Suspended until explicit user restoration** | `picsee-wt/opus-auditor` (detached) | do not dispatch or auto-restore |
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
log. Immediately after every implementation, fix, audit or confirm dispatch, start the attached listener. Paste the
active delegator Codex thread UUID literally; never derive it from cached `herdr agent_session` data, which has been
observed to point at a stale, wrong session. The helper uses argv throughout and never types into the desktop UI.

One complete Codex implementation-round command is (the agent must put the line
`Report-Task: issue90-implementation-r1` in its unique report):

```sh
python3 .agents/skills/picsee-delegator/scripts/listen-notify.py start \
  --event 'issue90-implementation-r1-head-<sha7>' \
  --task 'issue90-implementation-r1' \
  --thread '<exact-delegator-thread-uuid>' \
  --agent 'gpt-imple-3' \
  --handoff "$HOME/.picsee/herdr/gpt-imple-3/issue90-handoff.md" \
  --handoff-marker 'issue90-implementation-r1' \
  --poll report \
  --interval 30 \
  --idle-grace-seconds 180 \
  --max-minutes 3000
```

Use `--poll handoff` for Kimi/Claude and add `--handoff-marker '## Fix round 1'` when a report is appended or
reused. `--poll idle` remains available where no unique report can be required. Report mode checks the expected
file's modification time against listener registration and requires exactly one line formatted
`Report-Task: <task ID>`, with the whole ID equal to both non-empty `--task` and `--handoff-marker`.
`Report-Task: issue90-r10` does not identify `issue90-r1`; duplicate identity lines are stale evidence.
It completes only on fresh report plus idle/done. If idle/done persists without a fresh report for the configured
grace period, it queues `missing-handoff` for reconciliation. A blocked status queues immediately. Working with
an old report stays pending until a status change or the bounded deadline. Neither idle nor a report alone means
acceptance. Every dispatch or rearm gets a new `--event` and matching `--task`; include the round and expected head or
other unique token. Reusing an event with a different agent, task, target thread, poll argv or report path is rejected.

The start command detaches a new process session, so it survives the parent shell and agent turn. Runtime state is
under `~/.picsee/herdr/delegator/listeners/<event>/`: `config.json`, `pid`, `listener.log`, `status.json`,
`poll-result.json`, and, only after a successful `codex queue` response, `queue-receipt.json`. The shipped pollers
have a listener-enforced overall deadline of `--max-minutes` plus one poll interval and 10 seconds. If a poller
hangs inside `herdr`, the listener terminates its private poller process group, records `timeout` in
`poll-result.json`, and continues to queue a **needs inspection** message. The private group leader remains alive
until cleanup after either a normal poller exit or a deadline, so a poller cannot leave a same-group child running after
its result is recorded; failed cleanup records a poll error for inspection. Queue delivery uses finite 30-second
attempts and bounded exponential backoff. No heavy lock is taken. A nonzero poller exit, timeout, blocker,
question, `missing-handoff`, or missing/stale report is still queued as **needs inspection** and is never labelled
successful or accepted.

Inspect `status.json` and `poll-result.json` first. A `queue-receipt.json` proves only that Codex accepted the queued
message; it is not the delegator's ACK and poll completion is not audit acceptance. Before relying on this mechanism
for a new environment, run one user-authorized probe event, confirm the exact target thread visibly receives it, ACK
it there, and then continue the real work. Do not make the helper accept an audit, merge, or advance a lifecycle
unattended.

Failed delivery keeps the poll result and can be restarted with the identical command; repeats after a receipt do
not queue again. Registration and delivery are serialized per event without holding a duplicate lock through the
long poll. There is an unavoidable at-least-once edge: if `codex queue` accepts the message and the listener crashes
before writing its receipt, a retry can duplicate the notification. Treat event IDs and message labels as the
deduplication aid, not as an exactly-once transport guarantee.

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
| opus-auditor (p6) | No requests while suspended | Only an explicit user restoration reactivates it; a quota reset does not. Then re-establish the fresh-context procedure before use. |
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
  → blind audit → verdict → fix round (± confirm) → rebase → gates → gardener → PR → CI → merge
  → device validation → validation record PR → timeline / handoff log
```

Risk tier decides the audits:

| Tier | Typical scope | Audit |
|---|---|---|
| Low | docs, ledger wording, mechanical renames, tiny scripts, Low audit follow-ups | gpt-auditor alone, one blind round; apply the shared severity policy in §5.5 to every finding |
| Medium | ordinary features, UI states, navigation, scanning | gpt-auditor alone; one fix round for user-visible/AC Mediums, no confirm |
| High | FileAccess/sandbox/bookmarks, entitlements, concurrency core, anything that can lose data or access | gpt-auditor alone; every C/H gets a fresh-context confirm; cap of three rounds |

Raise the tier if a change touches FileAccess, AccessIntent, the loader, entitlements, Info.plist or signing.
This GPT-only table is an active temporary user override. The prior dual-audit baseline stays suspended until the user
explicitly restores Opus; never infer restoration from quota availability.

### 5.1 Issue

`gh issue create --title "<WP>: <summary> (<ledger IDs>)" --body-file … --label ready-for-agent`. The body says
what happens today (with evidence), what is wanted, constraints, ledger IDs and tier. For a user decision, quote
the user's words.

### 5.2 Brief (implementer task document)

Put it at `~/.picsee/herdr/<implementer>/<item>-brief.md`. Templates that worked:
`~/.picsee/herdr/delegator/p1-brief-P1-02.md`, `p2-brief-P2-01.md`, `p2-brief-P2-02.md` (long, for Codex) and
`~/.picsee/herdr/kimi-imple-1/issue82-brief.md` (short, for Kimi). A brief contains:

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

Put each request at `~/.picsee/herdr/delegator/<item>-audit-gpt.md` and its report at
`~/.picsee/herdr/gpt-auditor/<item>-r<round>.md`, ending with the VERDICT block. Reset gpt-auditor to fresh context
before every audit and confirm. Do not dispatch opus-auditor until the user explicitly restores it.

**gpt-auditor cannot take the heavy lock in its sandbox.** Tell it: "Do not run Swift tests; judge from source and
supplied owner gate evidence." The delegator reruns applicable gates; no absent second auditor is implied.

Every request carries:
- item, exact range `base..head`, worktree, commit list, and the note "objects are shared; use git show/diff";
- tier with the reason and the raise-the-tier triggers;
- dimensions D1–D12 and the pointer to `~/.picsee/herdr/delegator/audit-brief.md` (blind, read-only, no gh, scratch
  isolation);
- inputs: brief, amendments, handoff ("a claim to test"), evidence dir, receipts command;
- "Judge specifically", 5–10 bullets on the risky points;
- for a new implementer, ask gpt-auditor for an "Implementer assessment" paragraph.

Dispatch only gpt-auditor. Its round-one request is blind to previous audit conclusions. For a C/H confirm, reset it
again so the confirmation begins in fresh context, then provide the earlier finding, merged/sole verdict, fix range,
and counter-proof inputs required to judge closure.

**Confirm requests** (`<item>-confirm-gpt.md`; template `p2-02-confirm-gpt.md`) list each finding in scope
with its requested fix, the fix diff range, any rebase, and "Still open (do not re-judge)". They ask for
CLOSED/PARTIAL/OPEN per finding plus any new C/H.

**Challenge mode is unavailable** under the sole-auditor override. Resolve doubtful C/H with counter-proof or a fix,
then use the required fresh-context gpt-auditor confirm.

### 5.5 Applying the verdict and severity policy

- **Critical/High** blocks. Fix round, then a fresh-context confirm from gpt-auditor; cap of three rounds.
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
- **Claude:** the `picsee-doc-gardener` subagent.
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
- **Review**, the gpt-auditor rounds plus a Still open list; do not claim dual review while Opus is suspended;
- **Gates**, with numbers;
- the `无用户可见变化` lines;
- the exact `Ledger-Gardener:` line;
- the attribution line.

Then wait for CI and merge:

```sh
for i in $(seq 1 20); do [ "$(gh pr checks $P | wc -l)" -gt 0 ] && break; sleep 15; done   # checks may not register at once
gh pr checks $P --watch --interval 30; gh pr merge $P --rebase; git pull --ff-only origin main
```

---

## 6. Device validation (macos-device-test)

The validation role belongs to someone other than the implementer; the delegator has been doing it. Read
`.claude/skills/macos-device-test/SKILL.md` and `features/*.md`. Device runs happen only on the mini.

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
- `.agents/skills/picsee-delegator/scripts/panel-choose.sh RUN PATH`: in an open NSOpenPanel or powerbox, press ⌘⇧G, type the path via System Events
  `keystroke`, then Return twice.
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
- Report budget. Codex weekly usage shows in Codex panes ("weekly limit: N% left"). Opus quota recovery does not
  reactivate opus-auditor; only an explicit user restoration does.

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
| Missed that an implementer had finished (twice) | A screen-based poller ended with only a local log | Attach `listen-notify.py start` to `poll-idle.sh`; pin the exact delegator thread and inspect queue receipt vs ACK |
| `reset.sh` prints `FAIL … after /new` | pane too small to show "Context 0% used" | `herdr pane zoom`, read again; usually the reset did work |
| Prompt sent right after a reset "didn't land" | chooser still open or the pane redrawing | wait, check for "esc to interrupt" after ~20 s, resend |
| A mid-rebase commit swallowed the implementer's message | `git rebase … | tail` hid the conflict | never pipe a rebase; check its exit code |
| Rebase loop broke on `for f in $c` | zsh doesn't word-split unquoted variables | use `${=c}`, or compare the whole string |
| Python heredoc with Chinese text failed with "Non-UTF-8 code" | shell mangled bytes on stdin | write the script to a file (Write tool) with `# -*- coding: utf-8 -*-` |
| `log show` failed with "too many arguments" | zsh builtin `log` shadows `/usr/bin/log` | call `/usr/bin/log` |
| Coverage awk printed `lines /` | wrong lcov path | `swift-lcov.sh` writes `coverage/lcov.info` |
| `key.sh` typed letters instead of Tab/Esc | `key.sh` is single-character only | `kc.sh` with keycodes |
| Open panel path couldn't be typed | `key.sh` is one character | `scripts/panel-choose.sh` (System Events keystroke; disclose it) |
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
| Audit reports | Active: `~/.picsee/herdr/gpt-auditor/<item>-r<n>.md`, `-confirm.md`; historical Opus reports remain evidence but receive no new dispatches |
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
- **Auditors:** active temporary override: all tiers use only gpt-auditor, reset to fresh context before every audit
  and C/H confirm. User decision: 「目前opus auditor qouta 不够用了，暂时停用opus-auditor，只由gpt-auditor 来审」.
  Do not restore Opus automatically when quota returns; wait for an explicit user restoration.
- **Ledger:** feature-ledger md and html are committed together.
- **Git:** force-with-lease is allowed only on the delegator's own unmerged PR branches.
- **Product decisions of 2026-10-24:**
  - ACCESS-03: a move or rename browses at the new place; reconnect is prompted only when the folder can't be found.
  - A folder opens on its first image by name, after the scan.

When in doubt, read the handoff log's latest entries, `gh pr list`, `gh issue list`, `herdr pane list` and each
pane's screen before acting.
