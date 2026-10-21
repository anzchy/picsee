---
name: macos-device-test
description: Run empirical device acceptance for picsee by driving the real, built .app with computer use, and write the docs/validation record that lets a feature-ledger row reach 真机. Use when a work item's acceptance depends on real windows, pixels, input or the sandbox — Retina backing pixels, cursor-anchored zoom, C chrome show/hide timing, focus, powerbox folder grants, bookmark restore after relaunch, light/dark, Filmstrip — and unit tests or XCUITest can't prove it. Covers building and identifying the bundle, launch, fixtures, evidence, and the verdict table.
---

# macOS Device Test (computer use) — picsee

Ported from mdpro's `macos-device-test` on 2026-10-21 and rewritten for a native Swift app. mdpro's traps
that came from Tauri and WKWebView are gone; the ones that come from macOS itself stay.

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

## 3. Build a bundle — never test a bare executable

Computer-use grants are keyed by **bundle identifier**, and so is the sandbox container. Only a built `.app`
with `Contents/Info.plist` has one. A command-line target or `swift run` gives you a window computer use can't
see and a process the sandbox doesn't treat as picsee.

```bash
pkill -x Picsee; sleep 1                                   # kill before you build (§4, trap 3)
export PATH=/opt/homebrew/bin:$PATH
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-<locked>.app/Contents/Developer \
xcodebuild -project Picsee.xcodeproj -scheme Picsee -configuration Release \
  -derivedDataPath build/DerivedData build > ~/.picsee/build.log 2>&1
# → build/DerivedData/Build/Products/Release/Picsee.app
```

Product and scheme `Picsee`, bundle identifier `io.github.anzchy.picsee` (decided 2026-10-21; P0-01 creates them). Run the build in the background; a cold Release build takes minutes. If you test a Debug build,
say so in the record: it's a different binary, and its performance numbers don't count.

**Signing matters for the sandbox.** The sandbox and security-scoped bookmarks only work in a signed app. Device-test builds are signed with the Apple Development certificate of team `GRT84NAK4T` (automatic signing, set in `project.yml`); a build that came out ad-hoc signed isn't a valid device-test build. Check with `codesign -dv --verbose=2 "$APP" 2>&1 | grep TeamIdentifier`.
Whether a bookmark created by one local build still resolves after a rebuild (a new signature) is
**unverified**; P0-04 must find out. Until then, a bookmark-restore check relaunches the *same* bundle, and
the record states which build created the bookmark and which one resolved it.

## 4. Verify you are testing the code you think you are

### Trap 1 — the stale installed copy

A copy in `/Applications` shares the bundle id, so `request_access(["Picsee"])` and `open -a Picsee` may
resolve to it. Always launch by absolute path (§5), and check the path of the running process.

### Trap 2 — a bundle older than the source

```bash
APP=build/DerivedData/Build/Products/Release/Picsee.app
find Packages/PicseeKit/Sources App -newer "$APP/Contents/Info.plist" -name '*.swift' | head
```

Any output means a source file is newer than the bundle: rebuild.

### Trap 3 — the stale *process*, which `ps` can't see

Replacing the bundle on disk doesn't replace the running process. macOS routes `open -a <path> <file>` into
an **already-running** instance, which keeps executing the old image. `ps` shows the right path and still
lies. Kill before you build, and check `ps -o pid,lstart,comm -p $(pgrep -x Picsee)` shows a start time
after the build finished.

The decisive check interrogates the running image: the app logs its build identity at launch. P0-01 should
embed the git SHA in `Info.plist` and log it once at launch through `Logger`, as a public field. Then:

```bash
defaults read "$PWD/$APP/Contents/Info" <GitSHA key>            # what's on disk
log show --last 5m --style compact --predicate 'subsystem == "io.github.anzchy.picsee"' | grep -i launch   # what's running
```

Both must equal `git rev-parse HEAD` of the code under test. Until P0-01 adds this, record the check as not
available and rely on kill-before-build plus `lstart`.

## 5. Launch

Launch the fresh bundle **by absolute path**, handing it the fixture:

```bash
open -a "$PWD/$APP" "$SCRATCH/S1/orientation-6.jpg"
```

Opening a file this way is a user-intent grant, so the sandboxed app can read *that file* without a dialog.
A **folder** grant is different: it must go through the powerbox (`NSOpenPanel`), driven with computer use.
Never work around the powerbox: no Full Disk Access, no entitlement change, no copying files into the
container to dodge the dialog.

**First-launch state.** To test a fresh install (no bookmarks, no preferences), the app's sandbox container
has to go. Deleting `~/Library/Containers/io.github.anzchy.picsee` is a destructive `rm -r`: do it only when the brief
lists it as a step the user approved, on the machine named, and record it.

## 6. Fixtures

Fixtures come from the `TestAssets/` manifest (P0-07; sets S1–S6 in plan §10.1). **Never personal photos.**
Copy the files into a scratch folder and open the copies: P5 editing and Save As can write next to an image,
and the committed originals must stay untouched.

A good fixture makes the screenshot **self-verifying**:

- **1:1 pixels:** a 1-px black/white checkerboard. At actual pixels it is crisp; any resampling turns it
  grey or moiré. A zoomed crop answers "is this 100%?" without measuring.
- **Zoom anchor:** a coordinate grid with labelled cells. The label under the cursor before and after zoom
  must be the same cell.
- **Orientation:** one image per EXIF orientation value 1–8, each showing an arrow and the word `TOP`.
- **Transparency:** an alpha gradient over a known pattern.
- **Large and broken:** S3's 48MP and 100MP images and a synthetic oversize header; S5's truncated and
  corrupt files.

## 7. Probe design

- **Probe symmetrically.** Zoom in N steps, then out N steps, at the same cursor point: the same zoom level
  must show the same cell under the cursor. Navigate forward, then back. A directional defect is invisible
  to a one-way sweep.
- **Hold still and re-check.** For chrome timing, wait with no input and note when the tools hide; then
  wake them by moving to the top edge. Repeat with a menu, the Inspector and Filmstrip open: those must hold
  the tools visible.
- **Probe the boundaries.** The first and last image, an image smaller than the window, an 800×680 window,
  a very long file name, a folder you're not authorized for, a relaunch.
- **Feel isn't measurement.** Plan §10 metrics need ≥30 samples with p50/p95 from signposts or logs. A
  device run that only looked smooth says "felt responsive, not measured".

## 8. Evidence

### Logs: unified logging, read by time window

```bash
START=$(date '+%Y-%m-%d %H:%M:%S')      # before interacting
# …drive the app…
log show --start "$START" --style compact --predicate 'subsystem == "io.github.anzchy.picsee"'
```

A negative claim ("nothing was logged while scrolling") is only credible inside a window like this.
Interpolated values that aren't marked `public` show as `<private>`; if a criterion needs one, that's a
logging defect to report, not a reason to guess.

### Screenshots

Prefer `zoom` on the region of interest over a full screenshot: it's more readable and exposes less of the
desktop. Screenshots live in the report folder (`~/.picsee/dtrack/reports/shots/` on the mini), **never in
the repo**. The repo is public.

## 9. The verdict table

Every run produces one row per acceptance criterion, keyed by ledger row ID, with an explicit verdict:

| # | Ledger row | Criterion | Result |
|---|---|---|---|
| 1 | VIEW-03 | Pixel under the cursor stays put, zoom in and out | pass |
| 2 | VIEW-02 | 1:1 checkerboard is crisp at actual pixels | **NOT VERIFIED** — mini is @1x |
| 3 | CHROME-01 | Tools hide after ~2.5 s, reappear at the top edge | **FAIL** — stays visible after a menu closes |

- A criterion you couldn't exercise is NOT VERIFIED, with the blocker named. Never upgrade it to pass.
- A criterion judged by feel says so.
- A FAIL carries the reproduction: exact inputs, expected value, observed value.
- **Confirm the root cause by reading the code, not by reasoning from pixels.** And establish whether
  suspect code is load-bearing before proposing to delete it.

## 10. Privacy and safety

- **Request every app in one `request_access` call, as the run's first computer-use step**, listing only
  what the brief needs (Picsee, plus e.g. Finder for drag-in). Grants last only for the session, and each
  run starts with `/clear`.
- Take the minimum screenshots needed. Never save one into the repo.
- **Never change system, privacy or security settings** to unblock a test, and never click a web link.
- **Menu-bar utilities** may own menu-bar coordinates and block clicks there. Don't request access to them;
  use the keyboard shortcut for the command, or record NOT VERIFIED.
- **Escape and other keys:** in mdpro (a WebView) the computer-use `key escape` arrived only as a key-up.
  Whether a native `keyDown` reaches picsee through the tool is **unverified**. The first run with an Esc
  criterion checks it against the log and records the result here. If it fails, plan Esc as a user step.
- **Input method:** switch to ABC before key checks; an IME can swallow keys.

## 11. Recording the result

- Write the record to `docs/validation/P<n>.md`, a section per run: date, machine/chip/memory/macOS,
  display and scale, bundle path, git SHA (and how it was verified, §4), fixtures, the verdict table,
  deviations and NOT VERIFIED reasons. Mention each ledger row ID it covers; the gardener matches on them.
- A row can move to `验证 = 真机` only from a record like this, written by the device tester. Raising a row
  to `Shipped` is still the owner's edit, never the gardener's, and it doesn't change that row's 怎么确认 in
  the same commit (see `docs/feature-ledger.md`).
- A defect found here is a bug: it goes back through `/tdd-guardian:workflow` with a regression test that
  fails without the fix. This lane finds defects; it doesn't license an ad-hoc patch.
- After a fix, rerun the whole criteria table, not only the row that failed.

## Checklist

```
[ ] The criteria genuinely need a real window, pixels, input or the sandbox (§1)
[ ] Machine chosen; Retina rows go to the MacBook or are NOT VERIFIED (§2)
[ ] Killed picsee, then built the .app with the locked Xcode (§3)
[ ] Bundle newer than every source file under test (§4 trap 2)
[ ] Running process started after the build; build SHA matches HEAD (§4 trap 3)
[ ] One up-front request_access listing every app the run needs (§10)
[ ] Launched by absolute path on scratch copies of TestAssets fixtures (§5, §6)
[ ] Probed symmetrically, held still, hit the boundaries (§7)
[ ] Log window opened with a start time before interacting (§8)
[ ] Verdict table keyed by ledger row, NOT VERIFIED rows kept honest (§9)
[ ] No screenshots in the repo (§8, §10)
[ ] docs/validation/P<n>.md written; ledger rows left to the owner (§11)
```
