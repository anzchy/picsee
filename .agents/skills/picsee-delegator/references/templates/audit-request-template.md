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

UI review when this range changes visible UI (otherwise state `无 UI 变化`):
- Read [`docs/agents/ui-parity-contract.md`](../../../../../docs/agents/ui-parity-contract.md), the exact manifest/HTML, `design/DESIGN.md`, native mapping, plan §1.3, ledger rows, and the implementer brief's pinned design hashes. Check source SHA drift and any new native exception against its design authority.
- List affected states one by one with viewport, appearance, backing scale, real native entry and verdict: `PASS`, `FAIL`, `PENDING` (unimplemented), or `NOT VERIFIED` (uncaptured/blocked). A static HTML page does not prove native behavior.
- Review raw signed-App and HTTP-rendered HTML window screenshots with build/design provenance; compare measured regions (points versus backing pixels), spacing, typography/cropping, colors, icon/state changes, and declared masks. Reject post-hoc masks or an uncited system-control exception. If you cannot independently drive the device, say whose captures you inspected and keep that limit explicit.
- Check relevant actions, resize, light/dark, keyboard/focus, accessibility and zh/en text separately. Retake affected states from the fixed build and audit its new SHA. Do not clear all 20 pages or @2x based on a smaller sample; no `Shipped` upgrade from pixel resemblance alone.

Beyond the dimensions, judge these specifically:
- <5–10 bullets on the risky points: correctness traces, cancellation/generations, fences held, ledger honesty,
  tests discriminate, RED genuine, size rule>

Until the user explicitly restores Opus, use the sole independent `gpt-auditor` route. Do not launch the app or run device scripts. Do not run Swift tests in the auditor pane; judge code, original evidence and supplied gate outputs, and identify where a signed device run is still needed. Write ~/.picsee/herdr/gpt-auditor/<item>-r1.md with the report shape's VERDICT / COVERAGE / COUNT block. The delegator reruns owner gates; poll completion is not audit acceptance.
