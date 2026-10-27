# TDD plan — #127 fix round 1

Scope: the three findings in `issue127-fix-r1-brief.md` after rebase onto `origin/main`. FOLDER-03 remains Partial and device smoke belongs to the delegator.

### WI-1: Require UI parity evidence for deleted UI files

- A deletion-only Git diff under `App/UI/` or `PicseeMacUI/` fails an empty PR body.
- A populated state table plus a `Device-Smoke:` result passes; UI `n/a` fails, while a non-App change may use `n/a`.
- RED receipt: `ISSUE127-FIX1-WI-1` on `node-red`.

### WI-2: Preserve explicit JPEG input during a JPG-filtered scan

- With a `.jpeg` current input and an incomplete scan, selecting JPG keeps that input while another `.jpg` arrives first.
- No premature no-match or presentation change occurs; the later `.jpeg` batch keeps the input current.
- RED receipt: `ISSUE127-FIX1-WI-2` on `swift-red`.

### WI-3: Prove cleanup refuses unowned PID

- A PID file without a recorded birth/PID/executable identity never causes a signal.
- Offline device test only; the delegator performs signed device smoke before merge.
