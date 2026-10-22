# Picsee verification map

The run recipes for device-testing Picsee, one file per feature, keyed by feature-ledger row IDs. The ledger
(`docs/feature-ledger.md`) says **whether** a capability works and what proves it; these files say **how to
drive it** to get that proof. Read this index before a run, then use the matching feature file.

**Status: seeded from the plan, not yet driven.** The P0 recipes below were written before Picsee.app
existed. Their steps name user actions and observable results; the exact handles (accessibility
identifiers, menu titles) are filled in when P0-01 builds the UI, and each recipe is corrected on its first
real run.

## Baseline preconditions

- Machine and display as the brief names (SKILL.md §2): @1x runs locally on the mini; @2x rows run on the
  MacBook over SSH through its desktop-started tmux session, or are NOT VERIFIED until that path is set up.
- A fresh build of the code under test, signed by team `GRT84NAK4T`, launched by this run (SKILL.md §4–§5).
- Doctor passes every line (SKILL.md §6).
- No Picsee instance this run didn't start; the desktop's other computer-use driver idle (SKILL.md §3).
- Fixtures copied from `TestAssets/` into `$RUN_DIR/fixtures/` and hash-checked against the manifest.
- Sandbox container state as the brief says: either "existing" (left alone) or "fresh" (deleted with the
  user's approval, recorded).
- Input source ABC.

## Driving conventions

- Start every recipe from the baseline unless its preconditions say otherwise.
- Prefer keyboard shortcuts, then accessibility identifiers, then menu titles; coordinates last.
- Accessibility identifier convention: set in P0-01 and recorded here. (Pending.)
- Treat every key and menu name in a recipe as literal.
- Undo what a recipe changes (preferences, granted folders) when the brief asks for a clean machine
  afterwards; never delete evidence.

## Proof and skip reporting

- Capture the action and the resulting state, not only the final screen.
- Drive every entry point a row's 怎么确认 lists. Report each entry point on its own verdict line; an entry
  point you didn't drive is NOT VERIFIED and is never reported as verified through another one.
- Check anything persisted by quitting and relaunching; check anything written by reading the file.
- Name every artifact `<ledger-id>-<entry-point>-<state>.<ext>`, in `$RUN_DIR/shots/`.
- Report an unreachable path with the attempted action and the unmet precondition.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behaviour. It then
has exactly four H2 sections, in this order:

1. `Sub-features` lists the ledger row IDs it covers, one line each.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with computer use` starts with `Preconditions:` and pairs each user action with what to do
   and the observable result, as labelled bullets.
4. `Gotchas` lists traps that can waste or invalidate a run.

Keep implementation details out. Name only user paths, stable handles, required state and observable proof.
A recipe is written when its first row moves to `Partial`; a row can't reach 真机 without one.

## Known tool behaviour

Record here what a real run found out about the tools, so the next run doesn't rediscover it.

- Computer-use Escape on a native app: unverified (mdpro's WebView got only a key-up).
- Trackpad pinch: computer use has no pinch gesture; pinch entry points are a user step or NOT VERIFIED.

## Features

- [Actual pixels and anchored zoom](./canvas-pixels.md) covers 1:1 display and cursor-anchored zoom.
- [Open and grant a folder](./open-and-grant.md) covers a File Grant, the folder-grant prompt, restore after
  relaunch, and release on close.
- [Decode real images](./decode-images.md) covers formats, orientation, transparency, large images and broken
  files.
- [Keyboard and command routing](./keyboard-commands.md) covers the basic shortcuts and input-field and menu
  priority.
