@AGENTS.md

## Claude Code 补充

- 打开 PR 或推送 PR head 之前，先跑 `node scripts/ledger/garden-gate.mjs`；只有它输出 `RUN` 时，才用 `Agent` 调用 `picsee-doc-gardener`（`.claude/agents/picsee-doc-gardener.md`），传入模式 `pr`、分支 worktree 路径、base 和 head SHA。按 AGENTS.md「每个 PR 都要先跑 doc gardener」处理结果。
- 实现工作走 `/tdd-guardian:workflow`。`.claude/tdd-guardian/config.json` 还不存在，P0-01 建好工程后由用户运行 `/tdd-guardian:init`。P0-01 本身是唯一的 bootstrap 例外（先写失败测试、红/绿输出进 PR、无 receipt，见开发计划 P0-01）；除 P0-01 外，init 之前不做代码实现。
