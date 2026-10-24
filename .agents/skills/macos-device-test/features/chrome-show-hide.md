# Chrome show, hide and interaction locks

The viewer's bottom tools and window chrome stay quiet while viewing, return from deliberate edge or keyboard
input, remain visible during interaction, and close through the standard macOS commands.

## Sub-features

- `CHROME-01`: bottom tools, file name and traffic lights hide after about 2.5 seconds; hidden tools leave the
  accessibility tree and cannot be focused or hit.
- `CHROME-02`: the bottom edge recalls the tools, the top edge recalls the traffic lights, and Tab recalls and
  focuses the first tool; narrow layouts do not overlap.
- `CHROME-03`: an open menu, Inspector or keyboard focus locks the tools visible; ending interaction restarts
  the timer. Dragging and Filmstrip remain unavailable or NOT VERIFIED until their work packages land.
- `CHROME-04`: View › Always Show Tools prevents hiding while enabled. Persistence remains a P1-09/P3-11 check.
- `CHROME-05`: Esc from a tool returns focus to the canvas; Esc on a standalone image does not invent a grid.
- `CMD-01`: File › Close and ⌘W close the viewer window.

## How to get to it (user POV)

- Open a manifest-verified image and stop moving the pointer to let the viewer become quiet.
- Move the pointer into the bottom or top 32-point recall band, or press Tab.
- Use View › Always Show Tools; open the View menu or Inspector; move keyboard focus into a bottom tool.
- Resize the window through 640, 480 and 300 points wide.
- Press Esc from a bottom tool or the standalone-image canvas.
- Choose File › Close, or press ⌘W.

## Driving it with computer use

Preconditions: Mac mini @1x baseline; ABC input; an image copied into `$RUN_DIR/fixtures/` and listed in
`fixtures.sha256.json`; the image opened through the recorded bundle; starting doctor passes. Synthetic pointer
events are a disclosed substitute for a real mouse and do not verify real hover.

- **Read the AX tree safely.** In one System Events tell block, first assign `entire contents of window 1` to a
  variable, then inspect or return that variable. Do not repeatedly query `entire contents` inline. Record the
  roles, identifiers, titles, focused state, position and size needed for the current assertion. Visible chrome
  has seven pressable tool leaves plus `chrome.filename`; quiet chrome leaves only `viewer.canvas` in the window.
- **Idle hide.** Capture the visible AX inventory, leave all input idle for at least four seconds, assign the
  entire contents again, and confirm the tools and file name are absent. Capture the window and confirm the
  traffic lights are also absent. Do not infer VoiceOver speech from this AX-tree check.
- **Pointer recall bands.** Derive the owned window frame, then use a run-local, PID-checked CoreGraphics helper
  to post `CGEvent` events of type `mouseMoved`. Move first to the canvas middle (no recall), then within 32 points
  of the bottom edge (tools and traffic lights return), idle until hidden, then within 32 points of the top edge
  (traffic lights return without the bottom tools). Label the verdict as synthetic-pointer evidence.
- **Tab and Esc.** From quiet chrome send Tab with `scripts/device/kc.sh "$RUN_DIR" 48`; confirm tools return and
  Open… is focused, then Tab again to the next tool. Send Esc with `kc.sh "$RUN_DIR" 53`; confirm focus returns to
  `viewer.canvas`. On a standalone-image canvas, Esc keeps the same window and file title and does not show a grid.
- **Narrow-width overlap.** Set widths 640, 480 and 300 points with `size.sh`. From the saved AX-tree variable,
  compute every visible tool's frame from its AX position and AX size. Assert that no pair of rectangles intersects
  and every rectangle stays inside the window frame; record the line count at each width. At 640 points, post a
  disclosed synthetic click (`CGEvent`, like the record's `click.sh`) at the centre of Next's AX frame and confirm
  Next—not Zoom Out—runs. With no folder grant, the ACCESS-01 prompt appears; dismiss it with its Cancel button.
- **Interaction locks.** Focus a tool and wait at least four seconds; it stays visible. For the menu lock, find the
  View menu-bar item in the saved AX tree and invoke its `AXPress` action, confirm the menu is selected/open, wait
  at least four seconds, close it with Esc key code `53`, and confirm hiding resumes after about 2.5 seconds. Repeat
  the lock/release observation with Inspector opened by ⌘I. Keep drag and Filmstrip explicitly NOT VERIFIED.
- **Always show.** Choose View › Always Show Tools, wait at least five seconds and confirm the tools remain. Toggle
  it off and confirm the idle timer hides them. Do not claim relaunch persistence in this recipe.
- **Close commands.** From equivalent one-window starts, invoke File › Close through its menu item and ⌘W through
  `key.sh "$RUN_DIR" w command` separately. Confirm the owned process remains and its window count changes 1→0.
- **Proof.** Save only the minimum action/result screenshots and AX text under the run directory, named by ledger
  ID and entry point. Give menu, shortcut, pointer, and keyboard paths separate verdict lines.

## Gotchas

- `key.sh "$RUN_DIR" tab` and `key.sh "$RUN_DIR" escape` type text (and are now rejected as multi-character
  values); named keys must use the `kc.sh` codes above.
- A synthetic `mouseMoved` event proves the app's event path, not real-mouse hover. Keep real hover NOT VERIFIED.
- AX menu checkmarks may lag one refresh; re-read the tree after the action instead of trusting the old variable.
- Clicking Next without a folder grant opens the expected ACCESS-01 prompt; dismiss it with the prompt's Cancel
  button before continuing the recipe.
- Known Still-open from the P1-08 run: immediately after a pointer click on a tool, a following canvas key can
  remain with the native control instead of returning to the canvas. Record that path as FAIL until it is fixed;
  do not generalize the passing keyboard-focus path to it.
- `CHROME-01` VoiceOver speech, `CHROME-03` dragging/Filmstrip, `CHROME-04` relaunch persistence, `CHROME-05`
  grid-origin return, real hover and @2x remain NOT VERIFIED unless a later run exercises them directly.
