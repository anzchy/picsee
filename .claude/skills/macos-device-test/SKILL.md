---
name: macos-device-test
description: Run empirical device acceptance for picsee by driving the real, built Picsee.app with computer use, and write the docs/validation record that lets a feature-ledger row reach 真机. Use when a work item's acceptance depends on real windows, pixels, input or the sandbox — Retina backing pixels, cursor-anchored zoom, C chrome show/hide timing, focus, powerbox folder grants, bookmark restore after relaunch, light/dark, Filmstrip — and unit tests or XCUITest can't prove it. Covers machine choice, build, launch, doctor, the per-feature recipes in features/, evidence, cleanup and the verdict table.
---

# macOS Device Test (computer use) — picsee

Ported from mdpro's `macos-device-test` on 2026-10-21, rewritten for a native Swift app, and extended with
the structure of pstack's `create-verification-skill` (doctor, isolation, proof standards, cleanup, helpers,
a feature map, and a proof run of the skill itself).

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
| Mac mini (M4, 16 GiB, macOS 26.4, 1920×1080 @1x) | the plan §10 performance baseline; every check that doesn't need @2x | Retina criteria: record NOT VERIFIED (no @2x display) |
| MacBook Pro (M4, 24 GiB, macOS 27.0.1, Retina @2x) | Retina criteria (P0-03, P1-03, state page 27) | baseline performance numbers (not the §10.1 baseline) |

Runs on the mini go through the `picsee-dtrack` session; see the `remote-ssh` skill §6. Every record names
the machine, chip, memory, macOS version, display and scale.

## 3. Isolation: one instance per machine

Two Picsee instances must not be driven side by side on one machine. They share the bundle identifier, so
they share the sandbox container, preferences and bookmarks. Plain `open` may route to an existing instance;
`open -n` can create another, so isolation is checked before launch and the recorded PID identifies this run.
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
RUN_ID="$(date +%Y%m%d-%H%M%S)-<ledger-ids>"
RUN_DIR="$HOME/.picsee/device-runs/$RUN_ID"
scripts/device/build.sh "$RUN_DIR"
APP="$(cat "$RUN_DIR/bundle.path")"
```

The helper generates the project, then makes a signed **Debug** build in
`.build/device-<run-id>/` inside this worktree. It rejects modified, missing or untracked build inputs (including resources, plist, entitlements,
package files, test assets and project configuration), while allowing agent metadata in `.codex/`,
`.claude/` and `docs/`. It verifies the full input inventory against HEAD before and after the build,
refuses a running Picsee, records input hashes, the short/full SHA and machine facts in `build.json`, and
saves build output in
`build.log`. Generated package caches are excluded from build inputs. If the inherited Xcode stamp marks allowed
metadata edits dirty, the helper normalizes the verified build SHA and re-signs the bundle, preserving
entitlements and signature metadata. Debug performance numbers do not count as a
Release baseline. A Release performance run needs its own explicit build and record.

The locked Xcode is **26.6, build 17F113** (decided 2026-10-22, following the Mac mini). `PICSEE_XCODE` is `/Applications/Xcode.app` on the mini and `/Applications/Xcode-26.6.app` on the MacBook, where it sits beside Xcode 27.1; picsee is never built with 27.1. Confirm `xcodebuild -version` prints `Build version 17F113` before building. Product and scheme `Picsee`, bundle identifier
`io.github.anzchy.picsee` (decided 2026-10-21; P0-01 creates them). Run long builds in the background and monitor `build.log`. If you test a Debug build, say so in the record: it's a different binary, and
its performance numbers don't count.

**Signing matters for the sandbox.** The sandbox and security-scoped bookmarks only work in a signed app.
Device-test builds are signed with the Apple Development certificate of team `GRT84NAK4T` (manual signing: style, identity and team set in `project.yml`; Xcode 26.6's GUI won't open on macOS 27, so no Xcode account and no automatic signing); an ad-hoc signed build isn't a valid device-test build. Whether a bookmark created by
one local build still resolves after a rebuild (a new signature) is **unverified**; P0-04 must find out. Until
then, a bookmark-restore check relaunches the *same* bundle, and the record states which build created the
bookmark and which one resolved it.

## 5. Launch, and what "ready" means

Each run gets an ID and a run folder outside the repo. Evidence goes there and survives cleanup:

```bash
scripts/device/launch.sh "$RUN_DIR"
# Records bundle.path, picsee.pid, process.json (PID/path/birth), start.txt, ready.json and app.log.
```

The helper checks isolation, calls `open -n` with the absolute bundle path, finds the new PID by its exact
executable path, and records its executable path and process start time (`ps -o lstart=`) in `process.json` before checking
readiness. Old, missing, ambiguous or retired ownership records are refused; use a fresh run directory. It never picks a PID by owner name or newest
name match. The P0 skeleton run opens no fixture; it has one empty window.

For a future file-opening recipe, pass the scratch fixture through the app's normal open entry point.
Opening a file this way is a **File Grant**: the sandboxed app can read that file without a dialog. A folder
must become an **Access Root** through the powerbox (`NSOpenPanel`), driven with computer use. Never work
around the powerbox: no Full Disk Access, no entitlement change, no copying files into the container.

**Ready means usable, not just "a process exists":** exactly one accessibility window titled `Picsee` is
present, its PID has an on-screen layer-0 CGWindow, and the public launch log with the expected build SHA
has appeared. The P0 skeleton is an empty window; future recipes also confirm their fixture is displayed.
Time out after 30 s and report what was missing. An Automation/Accessibility failure stops immediately;
an interactive prompt is a blocker to report, never something to dismiss automatically.

**First-launch state.** To test a fresh install (no bookmarks, no preferences), the app's sandbox container
has to go. Deleting `~/Library/Containers/io.github.anzchy.picsee` is a destructive `rm -r`: do it only when
the brief lists it as a step the user approved, on the machine named, and record it.

## 6. Doctor: is this instance worth driving?

Run this read-only check first, and again whenever anything looks off. Every line must pass; a failing line
stops the run with that line as the reason.

```bash
scripts/device/doctor.sh "$RUN_DIR" --expected-sha "$(git rev-parse --short HEAD)"
```

The helper prints exactly one `PASS <check>` or `FAIL <check> — <why>` line for each check below, saves the
output atomically as `doctor.txt`, and exits non-zero if any fail. Collection errors become FAIL on the
affected checks; all twelve lines replace the previous report even when a bundle, plist or record is
missing or malformed. The twelve verdicts reach stdout before the report write. If storage fails, an
additional `FAIL report-write` line names the failure, the exit is non-zero, and an old report is moved to
`doctor.stale.txt` (or removed). If storage prevents both, the diagnostic explicitly marks the old
`doctor.txt` STALE/UNUSABLE. `doctor-input.json` keeps the observations.

| Check | Pass when |
|---|---|
| `build-sha` | `Info.plist`'s `PicseeGitSHA` equals the expected short SHA (defaults to this worktree's HEAD) |
| `bundle-id` | `CFBundleIdentifier` is `io.github.anzchy.picsee` |
| `signature-team` | codesign reports `TeamIdentifier=GRT84NAK4T` |
| `signature-valid` | `codesign --verify --deep --strict` succeeds |
| `sandbox` | the signed `com.apple.security.app-sandbox` entitlement is true (explicit XML from `codesign -d --entitlements :-`) |
| `process-bundle` | recorded PID, executable and process birth all match the live process; the record is active |
| `fresh-sources` | every build input matches the committed inventory and recorded hashes; none is newer than the bundle Info.plist |
| `single-instance` | the recorded PID is the only running process named Picsee |
| `window` | one snapshot of `properties of every window`, addressed by PID, contains one window titled `Picsee`; untitled windows become empty titles, and `0 windows` is distinct from an AX error |
| `launch-log` | this PID's unified log since `start.txt` contains `Picsee launch git=<expected SHA>`, unredacted |
| `machine` | model, chip, memory, macOS and main-display backing scale match `build.json`; check these against the brief too |
| `fixtures` | no fixtures for a skeleton run, or all fixture files match the run's `fixtures.sha256.json` |

For an image recipe, first verify the copies against `TestAssets/manifest.json`, then record the verified
relative paths and SHA-256 values as a JSON object in `fixtures.sha256.json`. Missing hashes with nonempty
fixtures fail. This fixture path has not been exercised by the skeleton proof.

The SHA in both the signed plist and the live process log matters: replacing a bundle on disk does not
replace an already-running image. A private or missing SHA never passes.

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

Capture the window, not a screen rectangle: a terminal can cover Picsee while a rectangle capture silently
records the terminal. The helper selects the on-screen layer-0 window by this run's PID and calls
`screencapture -l<CGWindowID> -o`, preserving native backing pixels without the shadow.

```bash
scripts/device/shot.sh "$RUN_DIR" P0-tooling-native-window
sips -g pixelWidth -g pixelHeight "$RUN_DIR/shots/P0-tooling-native-window.png"
```

Screen Recording is preflighted without requesting or changing permission. If missing, the helper prints
`FAIL` naming Screen Recording and exits non-zero. A temporary capture is decoded and sampled for visible
pixels; a black, transparent or empty result is rejected and removed before publishing the PNG. Existing
artifacts are never overwritten. The @2x MacBook proof is 960×672 pt → 1920×1344 px. Screenshots go to
`$RUN_DIR/shots/`, **never into the repo**. The repo is public.

## 11. Cleanup

Kill what this run started, by its recorded PID. Never by process name: `pkill -x Picsee` would also kill the
user's own copy.

```bash
scripts/device/cleanup.sh "$RUN_DIR"
ls "$RUN_DIR/shots" "$RUN_DIR/app.log" "$RUN_DIR/doctor.txt"
```

- Cleanup requires an active ownership record. It compares the live PID, executable path and birth time
  to `process.json`, validates again immediately before SIGTERM, and signals that PID only. An identity
  mismatch refuses action; an independently confirmed exited process is reported without a signal.
- Every cleanup attempt writes the `retired` marker, including refused or failed attempts. Retired records
  cannot drive cleanup, doctor, capture or input. Evidence stays intact; a new launch needs a new run folder.
  Capture and input also validate birth identity immediately before their action.
- No process-name kill and no escalation to SIGKILL. If SIGTERM does not finish within five seconds,
  report the failure. Never kill an instance this run did not start.
- Evidence and scratch copies remain in the run folder. No recursive deletion is part of cleanup.
- Restore the sandbox container only if the brief changed it, and only as the brief says.
- Run cleanup after a failed or aborted run too, so a broken attempt does not contaminate the next run.

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

- **When the computer-use provider offers `request_access`, request every required app in one call as its
  first step**, listing only what the brief needs. Start a fresh session for an independent acceptance.
  The shell-only P0 helper proof uses existing terminal Automation/Accessibility and Screen Recording
  grants; it does not manufacture a `request_access` call on a provider that has no such API.
- If an interactive permission prompt blocks a step, stop and report the question. Do not change privacy
  settings or click “Always allow” for anything other than Picsee.
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

Run build → launch → doctor → one observable smoke action → evidence → cleanup. Fix a helper defect with a
failing regression test, clean up each failed attempt, then rerun the whole sequence. Preserve explicit
NOT VERIFIED entries for features the skeleton cannot exercise.

**Proof run: 2026-10-22**, MacBook Pro M4, 24 GiB, macOS 27.0.1, internal Retina @2x, Xcode 26.6 (17F113),
signed Debug. Runtime implementation SHA `4037cb6`; run `20261022-issue4-fix2-proof` under
`~/.picsee/device-runs/`. Build → launch → doctor → window capture → resize/readback/restore → doctor →
cleanup passed. Both doctors printed twelve PASS lines. The window-only PNG is 1920×1344 for a 960×672 pt
window. `size.sh` set 800×600, a separate System Events call read 800×600, then size was restored to
960×672. Cleanup terminated PID 38809, retired ownership and preserved the PNG, logs and report. This
re-proves capture/input identity checks as well as launch and doctor. The following documentation commit
changes no runtime helpers. The post-build metadata-only re-sign branch is covered offline for success,
failure and clean-stamp bypass; that branch is still not live-proven. Earlier runs and RED/GREEN outputs
remain in the issue #4 handoff. This is helper proof, not independent feature-ledger acceptance.

Still **NOT VERIFIED**: Mac mini `picsee-dtrack`, XCUITest, and all `features/` recipes (the skeleton has no
image commands). On the mini, signed builds must run inside the user-owned `picsee-dtrack` tmux session;
direct SSH signing fails with `errSecInternalComponent`. Also unproven: keyboard helpers, native Escape,
fixture-hash runs, bookmark restore and the other future feature checks. No performance measurements.

Rerun the proof after changes to build, signing, launch, doctor or capture.

## 15. Helpers

Run from the worktree root. Requires Python ≥ 3.9, Node (tests only), macOS tools, XcodeGen on PATH and the
locked Xcode. `PICSEE_XCODE` overrides the Xcode application path, never the required build version.

```bash
export PATH=/opt/homebrew/bin:$PATH
RUN_DIR="$HOME/.picsee/device-runs/$(date +%Y%m%d-%H%M%S)-<ledger-ids>"
scripts/device/build.sh "$RUN_DIR"
scripts/device/launch.sh "$RUN_DIR"
scripts/device/doctor.sh "$RUN_DIR" --expected-sha "$(git rev-parse --short HEAD)"
scripts/device/shot.sh "$RUN_DIR" <ledger-id>-<entry-point>-<state>
scripts/device/size.sh "$RUN_DIR" 800 600       # points, prints the resulting size
scripts/device/key.sh "$RUN_DIR" o command   # example only; needs an implemented command
scripts/device/kc.sh "$RUN_DIR" 53           # example only; Escape remains unverified
scripts/device/cleanup.sh "$RUN_DIR"
node --test scripts/device/tests/device.test.cjs
```

`winid.js` can also be called as `osascript -l JavaScript scripts/device/winid.js <pid>`; its tab-separated
columns are window ID, PID, layer, width and height in points, and title. Selection ignores owner names.
The helpers copied from mdpro `scripts/redesign/device/` at `9f133f1d` were committed unchanged first,
then adapted locally; no mdpro checkout is needed to run them.

Offline doctor contract tests use `scripts/device/doctor.sh --fixture <observations.json>`; they test
verdict formatting and non-zero failures and do not constitute device evidence. Real doctor input lives
in `doctor-input.json`. The test runner uses harmless copied sleep processes. Node tests allocate `fs.mkdtempSync` directories
under `os.tmpdir()` and remove them in `after()`; Python offline fixtures use `TemporaryDirectory` with
cleanup. Tests never write under `~/.picsee/device-runs/`. Run evidence stays outside the worktree. Build artifacts remain
inside `.build/device-<run-id>/`. The heavy-lock integration is a TODO for issue #3.

## 16. Recording the result

- Write the record to `docs/validation/P<n>.md`, a section per run: date, machine/chip/memory/macOS, display
  and scale, bundle path, git SHA (and how it was verified, §6), fixtures, the verdict table, deviations and
  NOT VERIFIED reasons. Mention each ledger row ID it covers; the gardener matches on them. Evidence stays in
  `$RUN_DIR`; the record names the run ID.
- Commit the record on its own, touching nothing outside `docs/`, with a trailer naming the role and run:

  ```text
  docs(validation): P0-03 device run VIEW-02, VIEW-03 on MacBook

  Validated-by: claude-imple-1 run=<run-id>
  ```

  The gardener reads this trailer to rule out self-certification; a record without it can't lift a row.
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
[ ] Provider app grants or existing shell permissions confirmed; no privacy changes (§13)
[ ] Followed the feature recipe; every listed entry point driven (§7, §9)
[ ] Persistence and writes checked through a second view (§9)
[ ] Log window opened with a start time before interacting (§10)
[ ] Verdict table keyed by ledger row and entry point, NOT VERIFIED kept honest (§12)
[ ] Cleanup killed only our PID; evidence still in $RUN_DIR (§11)
[ ] docs/validation/P<n>.md written; ledger rows left to the owner (§16)
```
