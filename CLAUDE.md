@AGENTS.md

## Claude Code 补充

- 打开 PR 或推送 PR head 之前，用 `Agent` 调用 `picsee-doc-gardener`（`.claude/agents/picsee-doc-gardener.md`），传入模式 `pr`、分支 worktree 路径、base 和 head SHA。按 AGENTS.md「每个 PR 都要先跑 doc gardener」处理它的结果。
- 实现工作走 `/tdd-guardian:workflow`。`.claude/tdd-guardian/config.json` 还不存在，P0-01 建好工程后由用户运行 `/tdd-guardian:init`；在那之前不做代码实现。
