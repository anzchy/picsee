# Canvas fit, actual pixels, zoom, pan and full screen

At actual pixels, one image pixel maps to one physical (backing) pixel on whatever display the window is on,
and zooming in or out keeps the image pixel under the cursor under the cursor.

## Sub-features

- `VIEW-01` centred fit for landscape and portrait images, including resizing.
- `VIEW-04` bounded image dragging and restoring fit.
- `VIEW-05` full screen keeps the image and zoom mode (fit refits).
- `VIEW-02` actual pixels 1:1 on a @2x display, and still 1:1 after dragging the window from a @2x display
  to a @1x display. Pressing `1` directly on the mini's @1x display is additional evidence, not a replacement
  for the drag entry point.
- `VIEW-03` cursor-anchored zoom.

## How to get to it (user POV)

- Open landscape and portrait images, then resize the window; press `0`, View › Fit or Inspector Fit.
- Zoom in and drag the image; press `0` to restore its centred fit.
- Enter and exit full screen with ⌃⌘F, View › Enter/Exit Full Screen, and the green window button.
- Press `1` for actual pixels.
- Press `+` / `−` to zoom around the cursor.
- Pinch on the trackpad to zoom around the cursor.
- Run the actual-pixels check on both the MacBook's @2x Retina display and the mini's local @1x display.
- Drag the window from a @2x display to a @1x display and confirm it stays 1:1.

## Driving it with computer use

Preconditions:

- Mac mini with its local @1x display for VIEW-01, VIEW-04, VIEW-05 and additional @1x evidence for VIEW-02.
- MacBook Pro with its built-in @2x display for the @2x entry, reached over SSH with commands sent into its
  desktop-started tmux session. If that path is unavailable, record the @2x entry as NOT VERIFIED.
- A machine with both @2x and @1x displays for the drag-to-@1x entry. No current device-test machine has both
  scales, so record this entry as NOT VERIFIED.
- Fixtures: the 1-px checkerboard and labelled coordinate grid from S1, plus tier-①
  `synthetic/landscape-3x2.png`, `synthetic/portrait-2x3.png` and
  `synthetic/pan-grid-4096x3072.png`. Copy and hash-check them as the [runbook](../references/device-runbook.md) §8 requires.

- **Open the checkerboard.** Launch with the checkerboard fixture ([runbook](../references/device-runbook.md) §5). The image appears fitted to
  the window.
- **Additional actual-pixels evidence at @1x.** On the local mini, press `1`. A zoomed screenshot of the image
  centre shows crisp alternating black and white pixels, with no grey or moiré. This does not exercise the
  drag-to-@1x entry.
- **Actual pixels at @2x.** Repeat on the MacBook through its desktop-started tmux session. The checkerboard
  is still crisp; if the SSH/tmux path is not set up, record this entry as NOT VERIFIED.
- **Drag from @2x to @1x.** Drag the window from a @2x display to a @1x display and confirm the checkerboard
  stays crisp at 1:1. No current device-test machine has both scales, so record this entry as NOT VERIFIED.
- **Open the grid.** Open the coordinate-grid fixture and press `1`. Put the cursor on a labelled cell away
  from the centre and note its label.
- **Zoom with keys.** Press `+` four times, then `−` four times, without moving the cursor. After each press
  the cell under the cursor carries the same label.
- **Zoom with pinch.** Repeat the previous step with a trackpad pinch. This is a user step (computer use can't
  pinch); if the user isn't available, record VIEW-03 pinch as NOT VERIFIED.
- **Fit landscape and portrait on the @1x mini (VIEW-01).** Open
  `synthetic/landscape-3x2.png`, then `synthetic/portrait-2x3.png`, as separate File Grants. For each image,
  focus the AX image `viewer.canvas` and capture the window. Measure the image rectangle in the native @1x
  capture: all four image edges are inside the canvas and the two opposite leftover margins agree within one
  capture pixel on each axis. Record the measured edges and margins; appearance alone is not enough.
- **Resize and restore fit on the @1x mini (VIEW-01).** For each fixture, run
  `scripts/device/size.sh "$RUN_DIR" 800 680`, capture, then choose a second valid size that grows the window
  and capture again. Repeat the edge-and-margin measurement after each size: the whole image remains inside
  and centred. Press `0`, capture again and confirm the same fitted placement returns. Exercise View › Fit
  (`command.fit.menu`) and Inspector Fit (`command.fit.button`) on separate equal starting transforms if the
  run claims those entry points.
- **Pan to all four bounds on the @1x mini (VIEW-04).** Open
  `synthetic/pan-grid-4096x3072.png`, focus `viewer.canvas`, and press `1` for Actual Pixels. Start inside the
  visible image and use computer use's real mouse down → move → mouse up sequence to drag far toward the
  right, left, bottom and top, returning to the centred actual-pixel start with `0`, then `1`, between directions.
  Derive coordinates from the owned window and AX `viewer.canvas`, not hard-coded screen coordinates. If the
  provider lacks a drag primitive, send the same down/move/up sequence with a PID-checked input helper and
  disclose that substitution; the current repository helpers do not synthesize drag. At every bound, each
  axis on which the image is larger than the viewport has no blank gap at either edge; if an axis is smaller,
  the whole image stays inside it. Capture and measure all four bounds. Press `0`: the complete image returns
  to centred fit.
- **Full screen on the @1x mini (VIEW-05).** In fit mode, capture the window, press ⌃⌘F, wait for the transition,
  and capture full screen. The same image remains open and fit recomputes for the larger viewport. Open View
  and confirm the native title is Exit Full Screen; press ⌃⌘F again, then confirm the title is Enter Full
  Screen and the image is still in fit mode. Repeat the round trip after `1` and after one `+`: the image and
  selected actual-pixel/custom zoom mode remain, subject to the pan bound. Capture before, during and after
  each round trip.
- **Proof.** Zoomed screenshots `VIEW-02-1key-2x.png`, `VIEW-02-1key-1x.png`,
  `VIEW-02-drag-2x-to-1x.png`, and `VIEW-03-keys-step<n>.png` for each step. A NOT VERIFIED entry has no
  invented screenshot; name its blocker in the verdict table.

## Gotchas

- The local Mac mini is @1x only, so its `1` press is additional @1x evidence. The @2x entry belongs to the
  MacBook over SSH. Neither machine can exercise dragging one window from @2x to @1x; keep that entry
  NOT VERIFIED.
- Keep pinch NOT VERIFIED unless a person performs the trackpad gesture: computer use cannot synthesize it.
  Keep @2x NOT VERIFIED until the MacBook desktop SSH/tmux path is available, and keep cross-display drag
  NOT VERIFIED because neither device-test machine has both scales.
- Record whether VIEW-04 used a computer-use mouse drag or a synthetic down/move/up sequence. Evidence from
  one input source does not verify the other; mark the unexercised source NOT VERIFIED.
- A screenshot can itself be scaled. Use computer use's `zoom` on a small region and compare pixels, not a
  full-screen capture.
- Moving the cursor between key presses invalidates the anchor check; keep it still.
