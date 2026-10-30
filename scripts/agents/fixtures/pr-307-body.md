## Summary

Closes #232 (P2-08c T5, parent #227). While the folder a window shows has Lost Access, the sidebar keeps one row for it: the folder name, greyed, a ⚠ mark, collapsed, with no count and no subfolders. Nothing inside the lost folder is read. Recovery brings back the normal row, its subfolders and counts.

- Lost row (page 26 `.ds-nav-row.is-unavailable`): hover fill, muted name and folder icon, amber ⚠ on the current row (muted otherwise), collapsed chevron, same row height and insets as a normal row. Colours resolve against the row's effective appearance, so dark mode follows.
- VoiceOver: the row's label is the folder name; its value and help say 「无法访问」 plus page 26's cause wording (授权失效 / 外接磁盘未连接 / 找不到 / 无法访问此文件夹). New string: `Unavailable` / 「无法访问」.
- The window shows the lost row instead of clearing the tree; a known parent row is kept without reading it. Selecting the lost row starts no read and stays on page 26.
- When the shared access state refines the cause during one loss (for example 外接磁盘未连接 → 找不到 after a remount), every window rebuilds its row with the latest cause (fix round 1).

## Review (gpt-auditor)

| Round | Head | Result |
|---|---|---|
| Audit | `32050fc2` | C0 H1 M0 L0. F1 [High]: the row kept a stale cause after refinement within one loss; windows could disagree (AC-4, AC-5) |
| Fix 1 | `639588e7` | Row rebuilt from the waiting position with the latest cause, parent kept, no I/O. New App test drives diskNotConnected → notFound → accessExpired through the shared state in three windows (one opened mid-episode) and checks row AX against page 26 and unchanged read counts. RED `P2-08c-T5-WI-4` |
| Confirm | `639588e7` | C0 H0 M0 L0. F1 closed; no regression found on page 26, #231 rebind/Undo, recovery, another root, closed windows |

Still open: none.

RED receipts: `P2-08c-T5-WI-1` (swift-red), `WI-2`, `WI-3`, `WI-4` (app-red), all SEPARATION-HELD.

## Gates (delegator, serial under heavy-lock, head `639588e7`; ledger-only since)

- `swift test --enable-code-coverage`: 1319 tests in 36 suites passed
- lcov: lines 14550/14550, functions 2797/2797 (100%)
- `xcodegen generate`, `xcodebuild build` (CI, unsigned): exit 0
- App lane (`app-lane.mjs`, full): Tests run: 167, Failures: 0, Errors: 0
- `node --test scripts/tdd/*.test.mjs`, `ledger:html-check`, `git diff --check`: exit 0

## UI parity and device smoke (signed Debug, Mac mini @1x, zh-Hans, 1280×800)

Device-Smoke: PASS smoke-232-10302148 (signed Debug @1x, zh-Hans, non-implementer picsee-delegator, build 639588e7; ledger-only commits since)

| State | Result | Notes |
|---|---|---|
| Folder open, sidebar tree with counts | PASS | 相册H-232 12; 海岸与鸟居 7, 街巷 1, 山间与绿意 4 |
| Lost (moved to Trash), light | PASS | One greyed row, amber ⚠, collapsed chevron, no count, no subfolders; page 26 「找不到」 |
| Lost, dark (显示 › 外观 › 深色) | PASS | Same with dark tokens |
| Click the lost row | PASS | Stays on page 26; no tree or grid read |
| Recovery (folder moved back, app refocused) | PASS | Normal row, subfolders and counts back; grid 12 张图片 |

The pinned page 26 (`permission-denied.html`) was compared by eye; rendered-frame and colour assertions against its CSS run in the package tests. The in-app appearance preference was set back to 跟随系统 after the run.

Not verified: VoiceOver and AX on device (automated tests cover label, value and help); cause refinement on a real eject and remount; two windows on device; @2x; pixel-level parity.

## Ledger

ACCESS-04 限制 drops 「侧栏失效标记待 #232」 and says what the automated tests cover; ACCESS-04 and FOLDER-09 plan cells name P2-08c; A11Y-04 限制 names the new string as unit-only. No status or verification upgrade; acceptance text unchanged.

无用户可见变化：ACCESS-04 the 「#230」「#232」 prefixes and 「（PR 记录）未写入 docs/validation」 stay in 限制: they bound the evidence accurately, and moving them would lose that.

Ledger-Gardener: CLEAN 4a13df5..7ac5e01 (0 applied, 0 proposed)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

