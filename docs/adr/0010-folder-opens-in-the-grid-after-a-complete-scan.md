---
status: accepted
---

# A folder opens in the grid after a complete scan

Opening a folder (File › Open…, Choose Folder, dropping a folder) lands in the **Grid**, not the viewer. While the folder is
scanned the content area shows the **Reading State** (indeterminate, cancellable, inside the grid shell); only when the scan
completes does the full sorted Grid appear, with the first image in the sort order as the **Current Item** and nothing
selected; Space or Enter opens the viewer. Cancelling returns to whatever was shown before and never shows a partly scanned
folder. Opening a single image still goes straight to the viewer, and Esc from it returns to its folder's Grid when that
folder lies inside an Access Root. This supersedes the 2026-10-24 decision that a folder opens on its first image by name:
the grid entry (pages 11/12, and page 24 drawn inside the grid shell) contradicted it, and the same "after the scan"
rule now keeps the grid from reordering under the user, at the cost of no browsing before a large scan finishes.

User decisions, 2026-10-25 grilling (answers to the delegator's questions):
「打开一个文件夹……最终落在哪里？」→「网格，首张为当前项」;
「文件夹扫描尚未完成时，网格区域显示什么？」→「读取状态，完成后出网格」;
「从 Finder 双击一张图打开……此时按 Esc？」→「回到该文件夹的网格」;
「在 page24 读取状态时按「取消读取」，之后显示什么？」→「回到上一个状态」.

## Considered options

- Open the viewer on the first image after the scan (the 2026-10-24 rule), with the grid reached by Esc.
- A preference choosing between the two.
- Filling the grid incrementally while scanning, or switching to incremental filling after a timeout: rejected for
  reordering and two behaviours to test.
