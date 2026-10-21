---
name: macos-device-test
description: Run empirical device acceptance for picsee by driving the real, built Picsee.app with computer use, and write the docs/validation record that lets a feature-ledger row reach 真机. Use when a work item's acceptance depends on real windows, pixels, input or the sandbox — Retina backing pixels, cursor-anchored zoom, C chrome show/hide timing, focus, powerbox folder grants, bookmark restore after relaunch, light/dark, Filmstrip — and unit tests or XCUITest can't prove it. Covers machine choice, build, launch, doctor, the per-feature recipes in features/, evidence, cleanup and the verdict table.
---

# macOS Device Test (computer use) — picsee

Ported from mdpro's `macos-device-test` on 2026-10-21, rewritten for a native Swift app, and extended with
the structure of pstack's `create-verification-skill` (doctor, isolation, proof standards, cleanup, helpers,
a feature map, and a proof run of the skill itself).

> **Status: DRAFT.** This skill has never been run end to end, because Picsee.app doesn't exist until P0-01.
> It stops being a draft only after §14's proof run passes. Until then, treat every command here as the
> intended recipe, not a verified one.

This is the lane of last resort: slow, and it puts a real desktop on screen. Use it only for obligations the
automated lanes provably can't discharge. In the herdr roster it belongs to the device tester
(`claude-imple-1`), who is never the implementer of the work under test: a `Shipped` row whose validation
record was written by the implementer is self-certification, and the doc gardener flags it.

**Automation policy: automate every step that can be automated; bring in the user only where automation
truly can't work.**

- **Default executor:** computer use plus shell drives the whole run: clicks, keys, scrolling, focus changes,
  log reads.
- **When the user steps in:** only for a step with a known, recorded tool limit, or when an automated
  attempt fails because of the tool rather than the app. The brief names each such step up front; at that
  step the run stops, asks, then continues.
- **Verdict when the tool can't do a step:** NOT VERIFIED (tool limit), never FAIL. Rerun that step later
  with the user.
- **Record every deviation** where automation took a different path from a real user (e.g. activating the
  app instead of clicking its window).

## 1. When this lane is the right one

| The automated lanes can't see… | so this lane checks… |
|---|---|
| real backing pixels on a given display scale | 1:1 actual pixels, Retina sharpness, no resampling at 100% |
| the cursor in screen space | the pixel under the cursor stays put while zooming (anchor) |
| wall-clock chrome timing with real input | tools hide after ~2.5 s, wake on mouse-to-top, stay while a menu/Inspector is open |
| the sandbox powerbox | `NSOpenPanel` folder grants, the "not authorized" entry point |
| app relaunch | security-scoped bookmark restore, access released on close |
| the window server | traffic lights hiding with the tools, full screen, focus rings, light/dark |

**Do not use it** for anything a pure function or a fake can decide. Command routing, selection state,
`ViewerChromeState` transitions on a controllable clock, request cancellation and cache keys belong in unit
tests. XCUITest covers what can be scripted through accessibility. This lane confirms that the geometry,
timing and permissions feeding those tested modules are real.

## 2. Pick the machine

| Machine | Use it for | Can't do |
|---|---|---|
| Mac mini (M4, 16 GiB, 1920×1080 @1x) | the plan §10 performance baseline; every check that doesn't need @2x | Retina criteria: record NOT VERIFIED (no @2x display) |
| MacBook Pro (M4, 24 GiB, Retina @2x) | Retina criteria (P0-03, P1-03, state page 27) | baseline performance numbers (not the §10.1 baseline) |

Runs on the mini go through the `picsee-dtrack` session; see the `remote-ssh` skill §6. Every record names
the machine, chip, memory, macOS version, display and scale.

## 3. Isolation: one instance per machine

Two Picsee instances can't run side by side on one machine. They share the bundle identifier, so they share
the sandbox container, preferences and bookmarks, and macOS routes a second `open` into the first instance.
So:

- **One device run per machine at a time.** Never drive an instance this run didn't start (§5 records which
  one it started).
- **One computer-use driver per desktop.** On the mini, mdpro's `dtrack` session drives the same screen; check
  both sessions are idle before starting (`remote-ssh` §6).
- **The user's own Picsee is off limits.** If a Picsee is running that this run didn't start (an installed
  copy, a dev build from Xcode), stop and ask the user to quit it. Don't kill it.

## 4. Build a bundle — never test a bare executable

Computer-use grants are keyed by **bundle identifier**, and so is the sandbox container. Only a built `.app`
with `Contents/Info.plist` has one. A command-line target or `swift run` gives you a window computer use can't
see and a process the sandbox doesn't treat as Picsee.

Quit the previous run's instance first (§11 cleanup kills it by its recorded PID), then build:

```bash
export PATH=/opt/homebrew/bin:$PATH
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-<locked>.app/Contents/Developer \
xcodebuild -project Picsee.xcodeproj -scheme Picsee -configuration Release \
  -derivedDataPath build/DerivedData build > ~/.picsee/build.log 2>&1
APP="$PWD/build/DerivedData/Build/Products/Release/Picsee.app"
```

`<locked>` is the Xcode version P0-02 records. Product and scheme `Picsee`, bundle identifier
`io.github.anzchy.picsee` (decided 2026-10-21; P0-01 creates them). Run the build in the background; a cold
Release build takes minutes. If you test a Debug build, say so in the record: it's a different binary, and
its performance numbers don't count.

**Signing matters for the sandbox.** The sandbox and security-scoped bookmarks only work in a signed app.
Device-test builds are signed with the Apple Development certificate of team `GRT84NAK4T` (automatic signing,
set in `project.yml`); an ad-hoc signed build isn't a valid device-test build. Whether a bookmark created by
one local build still resolves after a rebuild (a new signature) is **unverified**; P0-04 must find out. Until
then, a bookmark-restore check relaunches the *same* bundle, and the record states which build created the
bookmark and which one resolved it.

## 5. Launch, and what "ready" means

Each run gets an ID and a run folder outside the repo. Evidence goes there and survives cleanup:

```bash
RUN_ID="$(date +%Y%m%d-%H%M%S)-<ledger-ids>"
RUN_DIR="$HOME/.picsee/dtrack/reports/$RUN_ID"; mkdir -p "$RUN_DIR/shots" "$RUN_DIR/fixtures"
START=$(date '+%Y-%m-%d %H:%M:%S')
open -n -a "$APP" "$RUN_DIR/fixtures/<fixture>"      # by absolute path, on a scratch copy (§8)
sleep 2; pgrep -n -f "$APP/Contents/MacOS/Picsee" > "$RUN_DIR/picsee.pid"
```

`-n` forces a new instance instead of routing into a running one; §3 already guarantees none is running.
Opening a file this way is a **File Grant**: the sandboxed app can read that file without a dialog. A folder
must become an **Access Root** through the powerbox (`NSOpenPanel`), driven with computer use. Never work
around the powerbox: no Full Disk Access, no entitlement change, no copying files into the container.

**Ready means usable, not just "a process exists":** the window is on screen showing the fixture, and the
launch log line with the build SHA has appeared (§6). Time out after 30 s and report what was missing.

**First-launch state.** To test a fresh install (no bookmarks, no preferences), the app's sandbox container
has to go. Deleting `~/Library/Containers/io.github.anzchy.picsee` is a destructive `rm -r`: do it only when
the brief lists it as a step the user approved, on the machine named, and record it.

## 6. Doctor: is this instance worth driving?

Run this read-only check first, and again whenever anything looks off. Every line must pass; a failing line
stops the run with that line as the reason.

| Check | Command | Pass when |
|---|---|---|
| It's ours | `cat "$RUN_DIR/picsee.pid"`, `ps -o pid=,lstart=,comm= -p <pid>` | the PID is alive and its path is `$APP`, not `/Applications` or Xcode's build folder |
| It's fresh | `find Packages/PicseeKit/Sources App -newer "$APP/Contents/Info.plist" -name '*.swift'` | no output (no source newer than the bundle) |
| It's the right image | `defaults read "$APP/Contents/Info" <GitSHA key>` and `log show --start "$START" --predicate 'subsystem == "io.github.anzchy.picsee"' \| grep -i launch` | both equal `git rev-parse HEAD` of the code under test |
| It's signed right | `codesign -dv --verbose=2 "$APP" 2>&1 \| grep TeamIdentifier` | `TeamIdentifier=GRT84NAK4T` |
| It's alone | `pgrep -fl 'Picsee.app/Contents/MacOS/Picsee'` | exactly one line, the PID above |
| The machine is as recorded | `system_profiler SPDisplaysDataType \| grep -E "Resolution\|UI Looks like"`, `sw_vers -productVersion` | matches the brief (and @2x for Retina rows) |
| Fixtures are intact | `shasum -a 256` on each fixture copy | matches `TestAssets/manifest.json` |

The SHA line can't pass until P0-01 embeds the git SHA in `Info.plist` and logs it at launch through `Logger`
as a public field. Until then, record "build identity: not available" and rely on the PID, path and `lstart`
lines. Why the SHA check matters: macOS routes `open` into an already-running instance, and replacing a bundle
on disk doesn't replace the process running it, so `ps` can show the right path while the old image runs.

## 7. Drive

- **Follow the feature recipe.** Each feature has a file in [`features/`](features/README.md) with its entry
  points, preconditions, steps and observable results. Run the recipe as written. If it's wrong, fix the
  recipe in the same change and say so in the record.
- **Stable handles first.** Prefer keyboard shortcuts and accessibility identifiers to coordinates. The
  identifier naming convention is set in P0-01 and listed in `features/README.md`. Coordinates are a last
  resort; they differ between the @1x mini and the @2x MacBook.
- **Probe symmetrically.** Zoom in N steps, then out N steps, at the same cursor point. Navigate forward, then
  back. A directional defect is invisible to a one-way sweep.
- **Hold still and re-check.** For chrome timing, wait with no input and note when the tools hide; then wake
  them. Repeat with a menu, the Inspector and Filmstrip open.
- **Probe the boundaries.** The first and last image, an image smaller than the window, an 800×680 window, a
  very long file name, a folder outside every Access Root, a relaunch.
- **Feel isn't measurement.** Plan §10 metrics need ≥30 samples with p50/p95 from signposts or logs. A run
  that only looked smooth says "felt responsive, not measured".

## 8. Fixtures

Fixtures come from the `TestAssets/` manifest (P0-07; sets S1–S6 in plan §10.1). **Never personal photos.**
Copy them into `$RUN_DIR/fixtures/` and open the copies: later work can write next to an image, and the
committed originals must stay untouched.

A good fixture makes the screenshot **self-verifying**:

- **1:1 pixels:** a 1-px black/white checkerboard. At actual pixels it is crisp; any resampling turns it grey
  or moiré.
- **Zoom anchor:** a coordinate grid with labelled cells. The label under the cursor before and after zoom
  must be the same cell.
- **Orientation:** one image per EXIF orientation value 1–8, each showing an arrow and the word `TOP`.
- **Transparency:** an alpha gradient over a known pattern.
- **Large and broken:** S3's 48MP and 100MP images and a synthetic oversize header; S5's truncated and corrupt
  files.

## 9. Proof standards

A criterion passes only with evidence that meets all of these:

- **The real user path.** Drive what a user would: menus, keys, clicks, the powerbox. No debug menus,
  test-only hooks, `defaults write` to set up state, or files placed in the container by hand.
- **Every entry point the criterion lists.** If the ledger's 怎么确认 says "pinch or +/−", drive both. An
  entry point you didn't drive is NOT VERIFIED for that row, and is never reported as verified through a
  different one.
- **The action and the resulting state**, not only the final screen: what you did, then what changed.
- **A second, independent view of anything persisted or written.** Persistence is checked by quitting and
  relaunching, then looking in the app. A file write is checked by reading the file (`mdls`, `exiftool`,
  `shasum`), not by the app's success message. A released Access Root is checked in the log, not assumed from
  a closed window.
- **Tagged.** Every artifact's name carries the ledger row ID and the entry point, e.g.
  `shots/VIEW-03-pinch-after.png`.

## 10. Evidence

### Logs: unified logging, read by time window

```bash
log show --start "$START" --style compact --predicate 'subsystem == "io.github.anzchy.picsee"' \
  > "$RUN_DIR/app.log"
```

A negative claim ("nothing was logged while scrolling") is only credible inside a window like this.
Interpolated values that aren't marked `public` show as `<private>`; if a criterion needs one, that's a
logging defect to report, not a reason to guess.

### Screenshots

Prefer `zoom` on the region of interest over a full screenshot: it's more readable and exposes less of the
desktop. Screenshots go to `$RUN_DIR/shots/`, **never into the repo**. The repo is public.

## 11. Cleanup

Kill what this run started, by its recorded PID. Never by process name: `pkill -x Picsee` would also kill the
user's own copy.

```bash
kill "$(cat "$RUN_DIR/picsee.pid")"; sleep 1
pgrep -fl 'Picsee.app/Contents/MacOS/Picsee' || echo "no Picsee left running"
rm -rf "$RUN_DIR/fixtures"                       # scratch copies only
ls "$RUN_DIR/shots" "$RUN_DIR/app.log"          # the evidence must still be here
```

- Cleanup removes the instance and the scratch copies, **never the evidence**: `app.log`, `shots/` and the
  report stay in `$RUN_DIR`.
- Restore the sandbox container only if the brief changed it, and only as the brief says.
- Run cleanup after a failed or aborted run too, so a broken attempt doesn't leave an instance that the next
  run would mistake for its own.

## 12. The verdict table

Every run produces one row per criterion and entry point, keyed by ledger row ID, with an explicit verdict:

| # | Ledger row | Criterion | Entry point | Result |
|---|---|---|---|---|
| 1 | VIEW-03 | Pixel under the cursor stays put, zoom in and out | `+`/`−` | pass |
| 2 | VIEW-03 | Same | trackpad pinch | **NOT VERIFIED** — computer use can't pinch |
| 3 | VIEW-02 | 1:1 checkerboard is crisp at actual pixels | `1` | **NOT VERIFIED** — mini is @1x |
| 4 | CHROME-01 | Tools hide after ~2.5 s, reappear at the top edge | idle, mouse | **FAIL** — stays visible after a menu closes |

- A criterion or entry point you couldn't exercise is NOT VERIFIED, with the blocker named. Never upgrade it.
- A criterion judged by feel says so.
- A FAIL carries the reproduction: exact inputs, expected value, observed value.
- **Confirm the root cause by reading the code, not by reasoning from pixels.** And establish whether suspect
  code is load-bearing before proposing to delete it.

## 13. Privacy and safety

- **Request every app in one `request_access` call, as the run's first computer-use step**, listing only what
  the brief needs (Picsee, plus e.g. Finder for drag-in). Grants last only for the session, and each run
  starts with `/clear`.
- Take the minimum screenshots needed. Never save one into the repo.
- **Never change system, privacy or security settings** to unblock a test, and never click a web link.
- **Menu-bar utilities** may own menu-bar coordinates and block clicks there. Don't request access to them;
  use the keyboard shortcut for the command, or record NOT VERIFIED.
- **Escape and other keys:** in mdpro (a WebView) the computer-use `key escape` arrived only as a key-up.
  Whether a native `keyDown` reaches Picsee through the tool is **unverified**. The first run with an Esc
  criterion checks it against the log and records the result in `features/README.md`. If it fails, plan Esc
  as a user step.
- **Input method:** switch to ABC before key checks; an IME can swallow keys.

## 14. Proving this skill (do once, then after big changes)

The first time Picsee.app can be built (after P0-01), run this skill end to end once: build, launch, doctor,
drive **one** feature recipe, collect evidence, clean up, then confirm the evidence still exists in `$RUN_DIR`.
Fix whatever fails, running cleanup after every failed attempt. Then:

- remove the DRAFT note at the top, and record the proof run's date, machine and SHA here;
- list anything the proof run skipped (e.g. it ran on the MacBook, so the mini's `picsee-dtrack` path is still
  unproven) — those steps stay unverified until a run covers them.

Rerun the proof after changes to the build, signing, launch or doctor sections.

## 15. Helpers

Planned, not yet written (they need Picsee.app to exist): `scripts/device/build.sh`, `launch.sh`, `doctor.sh`
and `cleanup.sh`, each wrapping the matching section above and printing one PASS/FAIL line per check. When
they're added, they must be executable, and this section must show how to call each one. Until then the
commands in §4–§11 are the reference.

## 16. Recording the result

- Write the record to `docs/validation/P<n>.md`, a section per run: date, machine/chip/memory/macOS, display
  and scale, bundle path, git SHA (and how it was verified, §6), fixtures, the verdict table, deviations and
  NOT VERIFIED reasons. Mention each ledger row ID it covers; the gardener matches on them. Evidence stays in
  `$RUN_DIR`; the record names the run ID.
- A row can move to `验证 = 真机` only from a record like this, written by the device tester. Raising a row to
  `Shipped` is still the owner's edit, never the gardener's, and it doesn't change that row's 怎么确认 in the
  same commit (see `docs/feature-ledger.md`).
- A row whose recipe in `features/` is missing can't reach 真机: write the recipe first.
- A defect found here is a bug: it goes back through `/tdd-guardian:workflow` with a regression test that fails
  without the fix. This lane finds defects; it doesn't license an ad-hoc patch.
- After a fix, rerun the whole criteria table, not only the row that failed.

## Checklist

```
[ ] The criteria genuinely need a real window, pixels, input or the sandbox (§1)
[ ] Machine chosen; Retina rows go to the MacBook or are NOT VERIFIED (§2)
[ ] No other Picsee running; no other driver on this desktop (§3)
[ ] Built the .app with the locked Xcode, signed by GRT84NAK4T (§4)
[ ] Launched by absolute path with -n; PID recorded; window ready (§5)
[ ] Doctor passed, every line (§6)
[ ] One up-front request_access listing every app the run needs (§13)
[ ] Followed the feature recipe; every listed entry point driven (§7, §9)
[ ] Persistence and writes checked through a second view (§9)
[ ] Log window opened with a start time before interacting (§10)
[ ] Verdict table keyed by ledger row and entry point, NOT VERIFIED kept honest (§12)
[ ] Cleanup killed only our PID; evidence still in $RUN_DIR (§11)
[ ] docs/validation/P<n>.md written; ledger rows left to the owner (§16)
```
