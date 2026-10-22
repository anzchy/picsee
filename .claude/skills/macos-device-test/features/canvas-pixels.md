# Actual pixels and anchored zoom

At actual pixels, one image pixel maps to one physical (backing) pixel on whatever display the window is on,
and zooming in or out keeps the image pixel under the cursor under the cursor.

## Sub-features

- `VIEW-02` actual pixels 1:1 on a @2x display, and still 1:1 after dragging the window from a @2x display
  to a @1x display. Pressing `1` directly on the mini's @1x display is additional evidence, not a replacement
  for the drag entry point.
- `VIEW-03` cursor-anchored zoom.

## How to get to it (user POV)

- Press `1` for actual pixels.
- Press `+` / `−` to zoom around the cursor.
- Pinch on the trackpad to zoom around the cursor.
- Run the actual-pixels check on both the MacBook's @2x Retina display and the mini's local @1x display.
- Drag the window from a @2x display to a @1x display and confirm it stays 1:1.

## Driving it with computer use

Preconditions:

- Mac mini with its local @1x display for additional @1x evidence for VIEW-02.
- MacBook Pro with its built-in @2x display for the @2x entry, reached over SSH with commands sent into its
  desktop-started tmux session. If that path is unavailable, record the @2x entry as NOT VERIFIED.
- A machine with both @2x and @1x displays for the drag-to-@1x entry. No current device-test machine has both
  scales, so record this entry as NOT VERIFIED.
- Fixtures: the 1-px checkerboard and the labelled coordinate grid from S1.

- **Open the checkerboard.** Launch with the checkerboard fixture (SKILL.md §5). The image appears fitted to
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
- **Proof.** Zoomed screenshots `VIEW-02-1key-2x.png`, `VIEW-02-1key-1x.png`,
  `VIEW-02-drag-2x-to-1x.png`, and `VIEW-03-keys-step<n>.png` for each step. A NOT VERIFIED entry has no
  invented screenshot; name its blocker in the verdict table.

## Gotchas

- The local Mac mini is @1x only, so its `1` press is additional @1x evidence. The @2x entry belongs to the
  MacBook over SSH. Neither machine can exercise dragging one window from @2x to @1x; keep that entry
  NOT VERIFIED.
- A screenshot can itself be scaled. Use computer use's `zoom` on a small region and compare pixels, not a
  full-screen capture.
- Moving the cursor between key presses invalidates the anchor check; keep it still.
