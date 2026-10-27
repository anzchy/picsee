---
status: proposed
date: 2026-10-28
---

# ADR-013：按用户旅程切片推进开发，J1+J2 为下一轮集成骨架

关联：开发计划 §1.3、§14；P3-01/02/10、P2-08、P3-16、ACCESS-01；`design/prototypes/picsee-browser/states/journeys.html`（目前在分支 `prototype/states-22-26`）；[ADR-014](0014-recoverable-folder-states-in-window.md)。

## 决定

picsee 的开发与验收**按用户旅程切片推进**。所谓切片，是从入口到结果的一条端到端路径，空态、错误和读取中状态都属于它。开发不按页面横向铺开，也不把单页做到完美再做下一页。

1. **旅程图是排序依据。** `states/journeys.html` 按用户旅程组织 20 份状态稿，共 J1–J4 四条旅程和一组参考页。每张卡片标注工作包和账簿实现进度。新的状态稿要么挂到某条旅程的某一步，要么进参考页，不允许游离。
2. **J1 + J2 是下一轮集成骨架。** 它不代替 MVP 门槛（§5 MVP 门槛原文不变）。
   - J1：首次打开（21，外观按 P3-16 的 B4）→ 读取文件夹（24）→ 网格（11）。支线：空文件夹（页 22）和权限失效（页 26）。
   - J2：网格（11）→ 沉浸大图（13）→ 唤回工具（14）→ 原始尺寸（27）→ Esc 回网格。支线：图片无法读取（页 25）。
   - 骨架另含三项：Finder 单图 → 目录授权入口（ACCESS-01，计划 P0-04）；返回时恢复选择和滚动；取消不回流旧图。
   - 骨架完成的标准：签名 App 端到端真机记录；@2x 只做 MVP 门槛已点名的项。
3. **约束贯穿骨架，不放到最后：**
   - 重启后授权恢复；
   - 失权后不读缓存；
   - 解码并发有上限；
   - 缩略图 backing scale 正确；
   - 尽早做一次 5000 项滚动压力探测。

   完整规模验收（P3-03…08）仍属发布门槛。
4. **切片内部的顺序：** 先用假数据把原生界面状态画对，再接真实数据与状态。空态、错误和读取中状态随所在旅程步骤一起交付。
5. **新界面先测原型：** 用 HTML 原型找 3–5 人走一遍旅程，再进入实现。适用于 B4、22-BD、26-BC 及以后的新状态。
6. **J1/J2 真机通过后，再扩到 J3 和 J4。**
   - J3：搜索、多选、右键。J4：Inspector、显示偏好。
   - 视觉对照按批做，约每 4–6 个 UI 工作包一批（UI 对照契约）。每个 UI PR 仍有设计自动断言和一次改动路径真机冒烟。
   - 未完成的旅程放在开关后，main 始终可发布。
7. **验收语言可借用 HEART 的 Task success**，例如"从首次打开到看见第一张图的步数、无错误"。不加遥测，也不写未测数字。

## 用户决定（原话）

- 2026-10-28 提问：「在 macOS App 开发的过程中，是把各个页面先实现出来再添加细节功能，还是说每个页面的功能做出来再去开发其他页面？也就是 User journey 中最佳的开发顺序是什么样的？」
- 「let codex weigh in on your suggestions」「also search for google and Meta, frontend design/ app design best practices」
- 「把这个顺序写进计划，通知 delegator」「相关事项，应该提一个adr」

## 考虑过的方案

| 方案 | 优点 | 问题 |
|---|---|---|
| 先把所有页面做出来，再补细节（横向） | 很快"每页都有" | 加细节前没有一条路径真正可用；异常状态被推到最后 |
| 一页做到完美再做下一页 | 单页质量高 | 交付的是"前轮"不是"滑板"（Kniberg），用户走不通一条旅程 |
| **按旅程切片，骨架先行，逐层加厚（选定）** | 每层都端到端可用、可真机验收；风险前置 | 需要维护旅程图并按旅程排期；须防止骨架被误当成 MVP 门槛 |

依据（2026-10-28 读取的一手资料）：
- Jeff Patton《The New Backlog》：故事地图的"脊柱"不排优先级；最上一层构成最小端到端系统，即 Alistair Cockburn 所说的 walking skeleton；"building up all major features a little at a time … never release a car without brakes"。
- Henrik Kniberg《Making sense of MVP》：先交付能用的滑板，而不是前轮。
- react.dev《Thinking in React》：先做静态版本，再找最小完整状态。
- Material 3 Designing › Flow：用例优先级决定流程优先级。
- GV Design Sprint：用逼真原型找真实用户测试。
- Google Research HEART 论文。
- engineering.fb.com《Rapid release at massive scale》：员工内部试用 → 2% → 100%，Gatekeeper 开关。

## Codex 只读评审的修正（已采纳）

- 近期工作**不是**"横向铺开"。计划本来就是 P0 风险 → P1 单图 → P2 连续浏览 → P3 网格。缺的是**验收收敛**。
- 旅程页的进度数字是卡片徽章计数，不是账簿统计。
- 有历史真机证据。应写"J1/J2 完整链路尚无当前验收证据"，不写"从未跑通"。

## 后果

- 计划 §14.7 记录按旅程的排序，并挂到既有工作包上，不新开阶段。
- `journeys.html` 目前在分支 `prototype/states-22-26`；入库 main 另走一个设计 PR，因为 `states/` 的目录与 manifest 受 PinnedDesign 测试和设计目录校验约束。进度徽章是手写快照，账簿变化时同步更新，页面图例注明数据日期。
- 骨架完成前，J3/J4 的新实现原则上不开工，已在进行中的除外。是否例外由用户决定。
- 本 ADR 不改变任何验收（"怎么确认"）文本与 MVP 门槛。
