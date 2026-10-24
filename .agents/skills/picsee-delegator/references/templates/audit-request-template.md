# Audit request: #<n> <WP> <summary> — round 1, blind

Item: <item>. Range: base <sha7>..<head7> on branch `<branch>`, worktree ~/Documents/mac-app/picsee-wt/<implementer>.
<N> commits, ~<lines> production lines. Objects are shared; use git show and git diff --no-ext-diff.
<main has moved to <sha7> (…); the rebase comes after audit — name conflict risks as notes only.>

Risk tier: **<tier>** (<why>). <Raise to High if it changes FileAccess, AccessIntent, the loader, entitlements or
Info.plist.> Audit D1–D12 at full depth from docs/agents/audit-dimensions.md on main (<tier> policy under the severity
table). Use the severity table, COVERAGE line and report shape exactly.

Rules: ~/.picsee/herdr/delegator/audit-brief.md (blind, read-only, no gh, scratch isolation).

Inputs:
- the brief: ~/.picsee/herdr/<implementer>/<brief>.md; scope amendments: <files>;
- the handoff, a claim to test: ~/.picsee/herdr/<implementer>/<item>-handoff.md; evidence in <dir>;
- receipts (Codex implementers): `node ~/.claude/plugins/cache/xiaolai/tdd-guardian/0.10.2/scripts/tdd-guardian/receipt.js show`
  from the implementer worktree. (Kimi: no receipts — judge the pasted RED/GREEN in the handoff.)

Beyond the dimensions, judge these specifically:
- <5–10 bullets on the risky points: correctness traces, cancellation/generations, fences held, ledger honesty,
  tests discriminate, RED genuine, size rule>

<!-- opus version: -->
Do not launch the app or run device scripts. Tests you may run, once: `scripts/heavy-lock.sh swift test --package-path
Packages/PicseeKit` in the implementer worktree (HEAD <head7>); change no tracked file; scratch replays must not write
into any worktree.
Write your report to ~/.picsee/herdr/opus-auditor/<item>-r1.md and end your final message with the
VERDICT / COVERAGE / COUNT block. <New implementer: add a short "Implementer assessment" paragraph.>

<!-- gpt version (replace the two paragraphs above): -->
Do not launch the app or run device scripts. Do not run swift test (your sandbox cannot take the shared heavy lock);
judge from source and the supplied gate evidence; the second auditor reruns the suite under the lock.
Write ~/.picsee/herdr/gpt-auditor/<item>-r1.md. Your final message is the report shape's VERDICT block.
