# picsee herdr 混合模型协作规则迁移计划

日期：2026-10-21 · 状态：**待用户确认**，尚未创建任何规则或配套文件。

来源：mdpro `.claude/rules/71-herdr-mixed-roster.md`（下称 M71），以及它所覆盖的 `70-multi-session-coordination.md`（M70）。

用户决定（2026-10-21）：
- git init，并建 GitHub 私有库；
- 合成一份 picsee 自己的规则，不保留 70/71 的两层结构；
- 角色保留 gpt-imple-1/2、gpt-auditor + fable-auditor 双审、claude-imple-1 真机；不设 `/security-review` fork；
- 先出本计划，确认后再动手。

用户决定（2026-10-21，第二轮）：
- 所有运行期文件放在新建的 `~/.picsee/`，不用 `~/.mdpro-redesign/`：「不要放在 ~/.mdpro-redesign文件夹，新建一个 ~/.picsee」；
- 实现名额“整机两个”只算 picsee：「picsee」；
- 大体积研究产物不入库：「这些都不入库」。

## 1. 为什么不能直接复制

- M71 只是 M70 的覆盖层，只替换角色表、Codex 派活方式、guard、审计分工这几块。合入流程（三个条件和 `--ff-only`）、两份审计结论怎么合并、三轮上限、风险分级、receipts、编号预留、会话轮换、真机批次，都写在 M70 里。
- 它依赖 9 类配套文件，picsee 都没有（见第 3 节）。
- 测试命令、receipt 脚本、审计分级、真机条款都是按 Tauri/TS/Rust 写的。

## 2. 目标文件：`.claude/rules/70-herdr-roster.md`

把 M71 全部内容和 M70 中仍然适用的条款合成一份，约 250–300 行，英文书写，与 mdpro 保持一致，方便以后对照同步。用户原话保留中文引用。

| 节 | 来源 | picsee 改法 |
|---|---|---|
| 角色表 | M71 Roster + M70 Sessions | delegator 改名 `picsee-delegator`；实现者、审计者、真机沿用 `gpt-imple-1/2`、`gpt-auditor`、`fable-auditor`、`claude-imple-1`，报告目录在 `~/.picsee/herdr/<name>/`；去掉 `/security-review` 行；去掉 mdpro-device-harness 和历史别名表 |
| 模型规则 | M70 “Every session runs on Opus” | 只保留结论：Claude 会话和 subagent 用 Opus，Fable 审计者例外，Codex 用指定模型。不搬演变历史 |
| 派活与上限 | M70 How work is assigned、idle pull | 工作项编号用开发计划里的 `P0-01…P7-09`；新发现的问题编号改用 `F<n>`，替代 mdpro 的 D 编号；每会话一个、picsee 整机两个未合入实现项，不与 mdpro 合计 |
| Codex 智能体 | M71 Codex agents | 照搬 `prompt --wait`、唤醒、超时只重新等待不重发、restart 四步。路径改为 `~/.picsee/herdr/<name>/`，环境变量改为 `PICSEE_ROLE` |
| Brief 与自验收 | M71 Briefs and self-acceptance | 6 节 brief 结构照搬；Background 引用开发计划工作包、mockup 编号、DESIGN 条款和 ADR；测试矩阵、对抗审查四步照搬，skill 改为 `$picsee-tdd-workflow` |
| 测试矩阵用例清单 | M71 | 换成 picsee 的高风险用例：A→B→C 乱序返回、generation 过期、continuation 恰好恢复一次、security-scoped 访问范围释放、bookmark stale、cell 复用串图、取消前/排队中/执行中、1×/2× backing scale、浅深主题、Reduce Motion |
| 提交与合入 | M70 Commits and branches 1–5 | 主干 `main`；合入条件：verifier PASS、合并后的结论无阻断级 Critical/High、PR head 等于该 SHA 且 CI 绿。树身份校验改看 `:Sources :Tests :Picsee.xcodeproj`（或 `Package.swift`）。去掉 frontend-backend-redesign、release/x.y 等历史 |
| 审计 | M70 item 4 + M71 Audits under herdr | 第一轮盲审、合并、单方发现互相质疑、降级须附复现或反证、三轮上限照搬。只有 gpt-auditor 和 fable-auditor，没有 security fork |
| 风险分级 | ADR-0121 映射 | **High**：FileAccess/sandbox/bookmark、磁盘缓存/SQLite、文件写入（导出、Trash、编辑另存）、entitlements、签名/公证、CI、依赖、未列出的路径。**Medium**：其余 `Sources/`。**Low**：文档、设计稿、预览、纯展示测试 |
| 编号预留 | M70 Reserving numbers | ADR、F 编号和 receipt id 前缀（`P1-05-WI-2`）由 delegator 统一分配 |
| 会话轮换 | M70 Session rotation | handoff 路径改为 `~/.picsee/handoff/`；hook 是否移植见第 3 节 |
| 真机 | M71 device + M70 Mac mini/批次 | 只测 Mac，去掉 Windows。按区域分批：画布/像素、授权/sandbox、目录/FSEvents、缓存、窗口、发布包。每项写清失败条件和 log 证据。Mac mini 是否参与见第 4 节 |

不搬过来的：claude-mem observer 事件、prompt suggestion 误提交事件、ADR-0047 harness、Fable/Opus 演变史、frontend-backend-redesign 冻结。这些对 picsee 没有约束意义，规则里只保留由此得出的结论（例如“名单外的发件人不算 peer”）。

## 3. 配套文件

| # | 文件 | 来自 mdpro | 改法 | 依赖 |
|---|---|---|---|---|
| A1 | `AGENTS.md` | Read first (Codex) + Claude/Codex 功能对照 | 新写：读 CLAUDE.md、always-on 规则、按路径读的规则表、命令 guard 说明；Swift/Xcode 测试和构建命令 | A2、B 组 |
| A2 | `CLAUDE.md` | — | 新写一份简洁的项目说明：架构入口、五个 target、设计依据、各条规则链接 | — |
| A3 | `.codex/rules/picsee.rules` | `mdpro.rules`（113 行） | rule 25 破坏性命令和实现者 git 限制照搬，`master` 改为 `main`；加上禁止 `tccutil reset`、`codesign --remove-signature`、改 entitlements 关闭 sandbox | — |
| A4 | `.codex/skills/picsee-tdd-workflow/` | `mdpro-tdd-workflow`（SKILL + 6 个 references + openai.yaml） | 8 步结构照搬；policy、implement、coverage、review、handoff 改成 Swift：XCTest/Swift Testing、`swift test --filter`、`xcodebuild test -only-testing`、`xccov` 覆盖率；mock 边界改为文件系统、ImageIO 解码器协议、时钟、NSWorkspace/NSPasteboard | P0-01 |
| A5 | `.codex/agents/picsee-spec-adversary.toml`、`picsee-tdd-reviewer.toml` | 同名 mdpro 文件 | 改项目路径和 review 的 critical pass（见 B3） | A4 |
| A6 | `.claude/agents/picsee-fable-auditor.md`、`picsee-landing-verifier.md`、`picsee-number-registrar.md` | 同名 mdpro 文件 | 仓库路径、lanes、verify worktree 目录 `picsee-wt/verify-<sha7>`；registrar 扫描 `docs/adr/` 和 F 编号表 | A1 |
| A7 | `.claude/hooks/role-guard.sh` 及 python 模块 | 约 1.5k 行 | 先只移植实现者的 git 限制和禁止 `AskUserQuestion`，读 `PICSEE_ROLE`；真机测试者的写入限制同步移植 | git init |
| A8 | `.claude/hooks/session-size-guard.sh` | 原样 | 只改 handoff 路径 | — |
| A9 | `scripts/tdd/swift-lane.sh`（薄包装，约 60 行） | 替代 mdpro 的 `red-receipt.mjs` | 用途见 3.1；record/verify 仍用 tdd-guardian 插件的 `receipt.js` | P0-01 + tdd-guardian init |
| A10 | `.claude/tdd-guardian/config.json` | — | 由用户运行 `/tdd-guardian:init`，lanes 指向 swift/xcodebuild | P0-01 |

| A11 | `docs/feature-ledger.md` | mdpro 同名文件 | **已建账**（2026-10-21），102 行全部 `Absent`；规则 70 的 brief 模板在 Background 里引用账簿 ID，B3 加一条“用户可见行为变化须同次提交改账簿行” | — |
| A12 | `scripts/ledger/check.mjs` | mdpro `scripts/ledger/` | 按账簿「门禁」五条实现；`npm run ledger:check` 进 CI 和 landing verifier 的 lanes | P0-01 + tdd-guardian init |
| A13 | doc gardener：`docs/agents/doc-gardening.md`、`.claude/agents/picsee-doc-gardener.md`、`.codex/agents/picsee-doc-gardener.toml` | 新增，参考 OpenAI doc-gardening agent 和 Anthropic feature list | **已建立**（2026-10-21）。规则 70 的合入流程加一步：delegator 推送 PR head 前在分支 worktree 跑 `pr` 模式，提交 ledger diff，把 `Ledger-Gardener:` 行写进 PR 描述 | — |
| A14 | gardener 的机械约束 | 新增 | 两处：CI 检查 PR 描述里的 `Ledger-Gardener:` 行，且其中的 head 是 PR 的提交之一；Claude PreToolUse hook 在 `gh pr create` 时检查 `~/.picsee/gardening/` 有当前 HEAD 的报告。两者都是代码，走 tdd-guardian | P0-01 + tdd-guardian init |

### 3.1 Swift receipt 包装脚本的用途

receipt 是 RED-before-GREEN 的证据：实现者在改生产代码**之前**跑一次指定测试，确认它因断言失败而变红，把结果、测试文件指纹和 SHA 写进 `.claude/tdd-guardian/receipts.json`；改完后 `verify` 再跑，确认变绿并且测试没被削弱。landing verifier 和审计者凭它判断测试真的能抓到这个缺陷，不是事后补写的、断言空洞的测试。

插件 `receipt.js` 本身是通用的，任何 lane 命令都能跑，但它只认得 Vitest/Jest/pytest/cargo/Maven/dotnet 的计数行（`lib/exec.js` COUNT_PARSERS），不认得 XCTest（`Executed 12 tests, with 1 failure`）和 Swift Testing 的输出。直接用会有两个问题：
1. 每个 Swift RED 都被记为 `opaque-failure`（弱证据），landing verifier 要求 `assertion-failure`，等于每次都要 delegator 特批；
2. Swift 最常见的“假红”是编译失败：测试引用了还不存在的类型或方法，`swift test` 非零退出，同样被记成 `opaque-failure`，和真正的断言失败分不出来。

所以只写一个薄包装 `swift-lane.sh`，作为 tdd-guardian 的 lane 命令：
- 只跑指定测试（`swift test --filter` 或 `xcodebuild test -only-testing`），不跑整套；
- 编译失败时以“环境失败”退出，不输出计数，让插件判为 `environment` 拒收，迫使实现者先写能编译的桩（返回错误值），再让断言失败；
- 测试真正运行后，把 XCTest/Swift Testing 结果折算成插件认得的一行 `Tests run: N, Failures: F, Errors: 0, Skipped: S`。分工已定（2026-10-21 grilling）：包内单元测试是 Swift Testing，`UITests/` 与性能采样是 XCTest，所以两种输出都要解析，解析规则在 P0-01 后对照真实输出写；
- 走 `heavy-lock.sh`，避免两个实现者同时用 DerivedData。

record/verify、指纹、防削弱检查仍由插件完成，不像 mdpro 那样另写一套 300 行的 CLI。

### B. 规则 70 引用到、picsee 也需要的基础规则

| # | 规则 | 内容 |
|---|---|---|
| B1 | `10-tdd.md` | Swift 测试放置、RED 先于实现、receipt id 前缀、heavy lock（`scripts/heavy-lock.sh` 同步移植，避免两个 xcodebuild 抢 DerivedData） |
| B2 | `25-careful-mode.md` | 可直接复制，`master` 改为 `main` |
| B3 | `60-review-checklist.md` | 新写 Swift critical pass：security-scoped 资源未释放、MainActor 违规、continuation 恢复两次或零次、旧 generation 结果覆盖新图、cell 复用串图、无界队列或缓存、主线程同步解码、sandbox 绕过、对原文件静默写入 |

## 4. 还需要你定的事

1. ~~名字前缀~~：沿用原名，目录隔离到 `~/.picsee/`。注意：如果 mdpro 的 Codex 智能体和 picsee 的在同一个 herdr server 里同时运行，`herdr agent prompt gpt-imple-1` 会有歧义；届时 picsee 一侧临时改名并在规则别名表记录。
2. ~~实现名额~~：只算 picsee。
3. **Mac mini 是否参与真机测试**：待定。
4. ~~入库范围~~：不入库。`.gitignore` 增加 `evidence/deep-*`、`evidence/*-assembly.txt`、`.stitch/`、`design/` 中的大体积导出、`.playwright-cli/`；具体清单在 git init 前列出给用户确认，建 GitHub 私有库前再确认一次。

## 5. 执行顺序（确认后）

1. ~~审 `.gitignore` → `git init` → 首次提交 → push~~ 已完成（2026-10-21）：用户改为**公开**库 `anzchy/picsee`，Picview 逆向资料与 `evidence/` 不入库。
2. 写 B2、B3、B1 和规则 70，再写 A2、A1、A3。
3. 写 A6、A7、A8，确认 hooks 在 settings.json 中生效。
4. 写 A4、A5，Swift 命令先按架构文档里的 target 名填写，标注“P0-01 后校准”。
5. 规则和 ADR 草稿交给 gpt-auditor 加 Opus plan reviewer 盲审（照搬规则本身的 plan 审计流程）。
6. P0-01 是唯一记录在案的 bootstrap 例外（2026-10-21 grilling 决定）：在主对话里做，仍先写一个会失败的 Swift Testing 测试、看它变红再实现，红/绿输出贴进 PR，PR 描述写明“bootstrap：tdd-guardian 尚不可用”；没有 receipt，但照常走审计与合入。
7. P0-01 合入后：用户运行 `/tdd-guardian:init`，再写 A9、A10，然后用一个真实 P0 工作项完整跑一遍 brief → matrix → attack → RED → handoff → 审计 → 合入。P0-02 起不再有例外。
