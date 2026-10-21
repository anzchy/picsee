# 用本机做功能验收：macos-device-test + doc gardener 使用指南

这份指南写给 picsee 的负责人（你）：一个功能开发完之后，怎么在**本机（MacBook Pro）**上用
`macos-device-test` 技能在真实 App 里验收，再用 doc gardener 检查功能账簿，最后带着证据开 PR。

> **当前状态（2026-10-21）**：Picsee.app 还不存在，P0-01 建好工程之后这条流程才能真正跑起来。
> `macos-device-test` 标着 DRAFT，要在 P0-01 之后完整跑通一次（技能 §14）才算可用。这份指南先把流程写清楚，
> 第一次真实运行后按实际情况修订。

## 1. 三件东西各管什么

| 东西 | 位置 | 管什么 | 不管什么 |
|---|---|---|---|
| 功能账簿 | [`docs/feature-ledger.md`](../feature-ledger.md) | picsee **现在有什么**：每行一项能力的状态、验证强度、代码位置、「怎么确认」（验收） | 怎么一步步操作 |
| `macos-device-test` 技能 | `.claude/skills/macos-device-test/` | **怎么在真实 App 里验**：构建、启动、doctor 自检、按 `features/` 的步骤操作、取证、清理、结论表 | 改账簿、改代码 |
| doc gardener | [`docs/agents/doc-gardening.md`](../agents/doc-gardening.md) | 每个 PR 前**检查账簿有没有过时或被放宽**：只做更谨慎的修改，升级一律交给你 | 跑 App、写验证记录、提交 |

三者的关系：账簿里的「怎么确认」是验收标准 → 设备测试按它在 App 里操作，写进 `docs/validation/P<n>.md` →
你根据记录升级账簿行 → gardener 检查这次升级有没有证据、有没有偷偷放宽验收。

## 2. 全流程一览

```text
功能实现完成（/tdd-guardian:workflow，单元测试全绿）
  │
  ├─ ① 找出要验的账簿行和每个入口
  ├─ ② 写 brief
  ├─ ③ 开一个新会话，跑 macos-device-test（本机）
  ├─ ④ 读结论表，写/提交 docs/validation/P<n>.md
  ├─ ⑤ 你按记录更新账簿行（单独提交）
  ├─ ⑥ 跑 picsee-doc-gardener（pr 模式）
  └─ ⑦ 按 gardener 结果处理，把 Ledger-Gardener 行放进 PR 描述，开 PR
```

发现 FAIL 时，不在验收会话里顺手改代码：回到 `/tdd-guardian:workflow` 先写一个会失败的回归测试再修，
修完重新从 ③ 跑**整张**结论表。

## 3. 本机一次性准备

只需要做一次，做完在 `docs/validation/P0.md` 里记一笔。

| 项目 | 怎么做 | 怎么确认 |
|---|---|---|
| Xcode | 安装 P0-02 锁定的版本（例如用 `xcodes install <版本>`） | `DEVELOPER_DIR=/Applications/Xcode-<版本>.app/Contents/Developer xcodebuild -version` |
| XcodeGen | 本机已装（`/opt/homebrew/bin/xcodegen`） | `xcodegen --version` |
| 签名 | 钥匙串里已有团队 `GRT84NAK4T` 的 Apple Development 证书（2027-01-31 到期） | `security find-identity -v -p codesigning` 里能看到它 |
| 终端权限 | 系统设置 → 隐私与安全性：给运行 Claude Code 的终端 App 打开**屏幕录制**和**辅助功能** | computer use 截图能看到桌面 |
| 输入法 | 验收前切到 **ABC** | 菜单栏输入法图标 |
| 运行目录 | `mkdir -p ~/.picsee/dtrack/reports` | 目录存在 |
| 已安装的 Picsee | `/Applications` 里不要有旧的 Picsee，或验收时它不在运行 | `pgrep -fl Picsee` 没有输出 |

本机是 Retina @2x 屏。账簿里涉及 2× 的行（VIEW-02 的前半、P0-03、27 页）**只能在本机验**；
VIEW-02 后半要求拖到 1× 外接屏，没有外接屏就记 NOT VERIFIED。性能数字不在本机测（计划 §10.1 的基准是 Mac mini）。

## 4. 逐步操作

### ① 找出要验的行和每个入口

在账簿里按工作包 ID 找行，例如 P0-03 → `VIEW-02`、`VIEW-03`。逐行读「怎么确认」，**把每个入口拆出来**：

> VIEW-03：触控板捏合**或**按 +/−，光标下的那个像素始终停在光标下
> → 两个入口：`+/−`、`触控板捏合`。两个都要验；只验一个，这一行最多 `Partial`。

再打开 `.claude/skills/macos-device-test/features/` 里对应的运行步骤（例如 `canvas-pixels.md`）。
**没有步骤的行先写步骤**，按 `features/README.md` 的格式：子功能、入口、操作与结果、陷阱。

### ② 写 brief

brief 是给验收会话的任务单，放在 `~/.picsee/dtrack/brief-<日期>-<ID>.md`（不进仓库）。至少写这些：

```markdown
# Brief 2026-11-05 VIEW-02-03

- 代码：分支 p0-03-canvas，HEAD <完整 SHA>，worktree <路径>
- 机器：本机 MacBook Pro，内建屏 @2x；外接 1× 屏：无
- 要验的行与入口：
  - VIEW-02：按 1（2× 屏）；拖到 1× 屏 —— 无外接屏，预期 NOT VERIFIED
  - VIEW-03：+/−；触控板捏合（用户步骤）
- 运行步骤：features/canvas-pixels.md
- 沙盒容器：保持现状（不删除）
- 需要用户动手的步骤：VIEW-03 触控板捏合 —— 到这一步停下来叫我
- 报告写到：~/.picsee/dtrack/reports/<run-id>/report.md
```

需要“全新安装”状态（删除沙盒容器）时，在 brief 里写明并注明“用户已同意”；验收会话不会自己删。

### ③ 开新会话跑 macos-device-test

在本机开一个**新的** Claude Code 会话（或在现有会话里先 `/clear`），不要用写这段代码的那个会话：
实现者不能给自己出验收记录。然后输入：

```text
/macos-device-test 读 ~/.picsee/dtrack/brief-2026-11-05-VIEW-02-03.md，按里面写的执行，报告写到 brief 指定的位置。brief 说需要我动手的时候停下来叫我。
```

会话会按技能顺序做：选机器 → 检查没有别的 Picsee 在跑 → 用锁定的 Xcode 构建并检查签名团队 →
`open -n` 启动并记录 PID → doctor 自检（每一行都要通过）→ 一次性申请 computer use 权限（只申请 brief 需要的 App，
你点一次“本次会话允许”）→ 按运行步骤操作 → 存日志和截图 → 按 PID 清理并确认证据还在。

你需要做的：

- 弹出 computer use 权限申请时，核对 App 列表后允许；
- 会话停下来叫你时（例如触控板捏合、按物理 Esc），照做后告诉它继续；
- 运行期间别动鼠标键盘，别切到别的 App。

截图和日志都在 `~/.picsee/dtrack/reports/<run-id>/`，**永远不进仓库**（仓库是公开的）。

### ④ 读结论表，写验证记录

报告里的结论表一行对应“一行账簿 × 一个入口”：

| # | 账簿行 | 验收 | 入口 | 结果 |
|---|---|---|---|---|
| 1 | VIEW-02 | 1:1 时棋盘格清晰 | 按 1（2×） | pass |
| 2 | VIEW-02 | 同上 | 拖到 1× 屏 | **NOT VERIFIED** — 没有外接屏 |
| 3 | VIEW-03 | 光标下像素不动 | +/− | pass |
| 4 | VIEW-03 | 同上 | 触控板捏合 | pass（用户步骤） |

核对三点：

1. 每个入口都有自己的一行；没验的写 NOT VERIFIED 和原因，不能空着，也不能被别的入口“顺带”算通过。
2. 写着“保留/退出重开/记住”的，要有退出重开后的证据；写文件的，要有读文件本身的证据；写“释放”的，要有日志行。
3. 报告开头的 doctor 全部通过，git SHA 等于要验的 HEAD。

然后由**验收会话**把记录写进 `docs/validation/P<n>.md`（一个运行一节：日期、机器/芯片/内存/macOS、屏幕与缩放、
App 路径、git SHA 及核对方式、素材、结论表、偏差、NOT VERIFIED 原因、运行 ID），并在节里写出每个账簿行 ID——
gardener 靠这些 ID 把记录对应到行。单独提交：

```text
docs(validation): P0-03 device run VIEW-02, VIEW-03 on MacBook
```

### ⑤ 你更新账簿行（单独提交）

只有你（owner）升级账簿行，gardener 和验收会话都不升级。按记录决定：

| 记录里的结果 | 这一行可以记成 |
|---|---|
| 所有入口 pass，含 1× 与 2× 两种屏（显示类） | 验证 `真机`；状态可到 `Shipped`，「怎么确认」末尾链接这份记录 |
| 部分入口 NOT VERIFIED | 状态最多 `Partial`，「怎么确认」加 `限制：`写明没验的入口 |
| 有 FAIL | 不升级；回到 tdd-guardian 修 |

两条硬规矩：

- **升级状态的那次提交，不能同时改这一行的「怎么确认」**（加 `限制：` 一句除外）。要改验收，单独提交并引用你的原话或 ADR。
- **不能靠删掉「怎么确认」里的入口让它升级**，删入口也算改验收。

上面例子里 VIEW-02 的 1× 没验，所以 VIEW-02 记 `Partial`、`限制：1× 外接屏未验`；VIEW-03 两个入口都过了，可以记 `真机`。

### ⑥ 跑 doc gardener

PR 之前（以及每次重新推送 PR head 之前），在 Claude Code 里说：

```text
用 picsee-doc-gardener 跑 pr 模式：worktree <路径>，base $(git merge-base main HEAD)，head <HEAD SHA>，分支 p0-03-canvas。
```

它读这次改动、对应到账簿行、检查证据，报告写到 `~/.picsee/gardening/<分支>-<head7>.md`，最后一行是 PR 用的结论行。

### ⑦ 按结论处理，开 PR

| 结论 | 意思 | 你做什么 |
|---|---|---|
| `CLEAN` | 没有过时的行 | 把 `Ledger-Gardener:` 行放进 PR 描述，开 PR |
| `UPDATED` | 它只做了允许的谨慎修改（路径改名、证据丢失降级、审查日期） | 看 `git diff -- docs/feature-ledger.md`，提交为 `docs(ledger): garden <base7>..<head7>`，再开 PR |
| `NEEDS-OWNER` | 有需要你决定的事：升级缺入口、缺第二次确认、可能的自我认证、该加新行 | 改它点名的行，或在 PR 描述里逐条写 `无用户可见变化：<ID> <理由>`，然后**重跑** gardener |
| `BLOCK` | 有升级没有证据，或升级的同时改了「怎么确认」 | 不开 PR：把验收改动拆成单独提交，或补齐真机记录 |

没有 `Ledger-Gardener:` 行的 PR 不进入审查。

## 5. 常见问题

**本机验和 Mac mini 验有什么不同？**
本机是 2× 屏，只用来验 Retina 相关的行和日常功能；Mac mini 是 1× 屏、16 GiB，是性能基准，走 `picsee-dtrack`
会话（见 `remote-ssh` 技能 §6）。记录里永远写清楚是哪台机器。

**computer use 做不到的操作怎么办？**
触控板捏合、可能还有 Esc（原生 App 能不能收到还没验证过），在 brief 里预先标成“用户步骤”。
你不在的时候，这一项记 NOT VERIFIED（工具限制），不能记 FAIL，也不能记 pass。第一次真实运行查清 Esc 后，
结论写进 `features/README.md` 的「已知工具行为」。

**doctor 没通过怎么办？**
看失败的那一行：有别的 Picsee 在跑 → 退出它（不要让会话去杀你自己的 Picsee）；构建比源码旧 → 重建；
签名团队不对 → 检查 `project.yml` 的签名设置；SHA 不一致 → 你验的不是你以为的代码，重建并重启。

**验证记录能不能由写代码的会话写？**
不能。账簿要求真机记录来自设备测试角色，gardener 会把“实现者给自己出记录”报成 `NEEDS-OWNER`。
**目前的已知缺口**：gardener 按提交作者判断，而本机所有提交的 git 作者都是同一个人，它分不出是哪个会话写的。
在这个判断改进之前，靠流程保证：验收一定在新会话里跑，验证记录的提交信息写明运行 ID。

**截图能不能放进 PR 或 issue？**
不建议。截图会暴露桌面内容，而仓库与 issue 都是公开的。PR 里放验证记录的链接和结论表即可；确实需要图时，
只用 computer use 的局部放大图，并确认画面里没有个人信息。

## 6. 相关文件

- 功能账簿规则：[`docs/feature-ledger.md`](../feature-ledger.md)「验证」「防止验收被悄悄放宽」
- 设备验收技能：`.claude/skills/macos-device-test/SKILL.md`，运行步骤在同目录 `features/`
- gardener 规程：[`docs/agents/doc-gardening.md`](../agents/doc-gardening.md)
- 开发计划与验收门槛：[`docs/PICSEE_DEVELOPMENT_PLAN.md`](../PICSEE_DEVELOPMENT_PLAN.md)
- 术语：[`GLOSSARY.md`](../../GLOSSARY.md)
