# 功能账簿

**picsee** · 首次建账 2026-10-21 · 分支 `main` · 依据 [分阶段开发计划 v0.2](./PICSEE_DEVELOPMENT_PLAN.md)

这份账簿只回答一件事：**picsee 原生 App 现在实际有什么**。每一项能力占一行，写明状态、代码位置，以及在运行中的 App 里怎么确认。

建账时还没有任何 Swift 源文件，所以每一行都是 `Absent`。这些行是**先写好的验收**：「怎么确认」现在就写成将来要做的操作，实现之后只改状态、验证、位置三格，验收不跟着实现降低（见「防止验收被悄悄放宽」）。

它不是 changelog、计划或 ADR。什么时候变的看 git 历史和 `CHANGELOG.md`；先后顺序与验收门槛看 `docs/PICSEE_DEVELOPMENT_PLAN.md`；为什么这样做看 `docs/adr/`；实测数据和过程记录看 `docs/validation/P*.md`。

浏览器原型 `design/prototypes/` 和 `design/prototypes/picsee-browser/states/` 里的 mockup **不算** picsee 的能力。它们是设计输入，在本账簿里不能把任何一行推到 `Absent` 以外。

## 状态

状态只能是下面五个词之一，枚举是封闭的：

| 状态 | 含义 |
|---|---|
| `Shipped` | 已实现，并在真机运行的 App 里按「怎么确认」验证通过 |
| `Partial` | 能用，**但有一条写明的限制** |
| `Stub` | 类型、接口或 UI 已存在，行为还没有 |
| `Absent` | 还没做 |
| `Unknown` | 依赖系统或第三方提供、在 picsee 里从未测过，不做任何声称 |

- `Shipped（仅 JPEG）` 这类写法算错。细节写进「怎么确认」。
- `Partial` 必须在「怎么确认」里写一条 `限制：`，说明限制是什么。
- 写着 `Stub` 的能力，对外不能说 picsee「有」。
- **功能开关后面的能力**：代码已合入但默认关闭（编译开关、隐藏设置），记 `Stub`，并在「怎么确认」里写明开关名。开关打开并通过真机验证后才能改 `Shipped`，同一次提交删掉开关或写明保留理由。

## 验证

「验证」一格记录**最强的一次证据**，也是封闭枚举：

| 验证 | 含义 | 对应 NASA 验证方法 |
|---|---|---|
| `无` | 没有证据 | — |
| `单元` | 自动化测试覆盖了逻辑，没有经过 App 界面 | Test（部分） |
| `集成` | 在 App 进程或 UI 测试里跑通，但不是人在真机上操作 | Test |
| `真机` | 按「怎么确认」在真实 Mac 上操作通过，`docs/validation/` 有记录 | Demonstration |

- `Shipped` 要求验证为 `真机`，且「怎么确认」里链接对应的 `docs/validation/` 记录。只有单元或集成证据的能力最多记 `Partial`，限制写「真机未验」。
- 涉及显示的行（1:1、缩放、Retina）要在 1× 和 2× 两种屏幕上都验证过，才算 `真机`。
- 性能类的行，数字写进 `docs/validation/`，本账簿只链接，不抄数字。
- **每个入口都要验。** 「怎么确认」用“或”“/”“、”列出的每个入口（按键、手势、菜单、按钮、拖入）和每个取值（如“JPEG 或 PNG”）都是验收的一部分，要分别验证。只验了一部分，最多记 `Partial`，`限制：` 写明没验的入口。没验的入口不能借另一个入口的结果算通过（例：VIEW-03 只按了 +/−、没试触控板捏合，就不是 `真机`）。
- **保存和写出要第二次独立确认。** 写着“保留”“退出重开”“记住”的行，要退出 App 再打开，在 App 里看到结果；写文件的行（导出、另存、去除元数据），要读文件本身确认（如 `mdls`、`exiftool`、`shasum`），不以 App 的成功提示为准；写着“释放”的行，以日志为准，不以窗口关了为准。
- `真机` 的记录按 `.agents/skills/macos-device-test/features/` 里该行的运行步骤做；还没有步骤的行，先写步骤再验证。

## 怎么写各列

| 列 | 写法 |
|---|---|
| ID | `区域-两位序号`，如 `VIEW-03`。一经分配不改、不复用；删掉的能力移到「不做」并保留 ID。brief、测试名、validation 记录都用这个 ID 引用 |
| 能力 | 用户能感知到的一件事，一行一件 |
| 计划 | 开发计划的工作包 ID，可多个，用 `、` 分隔。它说明这条需求从哪来；没有工作包的能力先补进计划再进账簿 |
| 在哪 | 路径从仓库根写起，放在反引号里，如 `Sources/PicseeViewer/ViewerSession.swift`。不写行号、不写计数、不写构建产物（`.build/`、`DerivedData/`）。`Absent` 写 `—` |
| 怎么确认 | 一个在 App 里能做的操作和应看到的结果，不是“看代码”。列出几个入口，就是几个都要验（见「验证」）。**不超过三句、约 150 字**；过程、截图、日志与历史写进 `docs/validation/`，这里只放链接 |

最后一条是从 mdpro 吸取的教训：mdpro 账簿的单元格逐渐长成上千字的修复史，没人能对着 App 一行行走下去。

## 防止验收被悄悄放宽

这一条参考 Anthropic 长时运行 agent 的 feature list 做法：功能列表一开始全部标为未通过，agent 只能改“是否通过”这一项，删改测试步骤被明确禁止，并且必须像真实用户那样端到端验证后才能标为通过。

- **状态升级的那次提交，可以追加或修改「限制：」文本，但不得改写「怎么确认」中的验收本身。确需改验收时，单独提交并在提交说明里引用用户原话或 ADR。**
- 升级状态的人不能是唯一的验证者：`Shipped` 的真机记录由真机测试角色（`claude-imple-1`）写，实现者不能自己给自己出记录。验证记录单独提交，带 `Validated-by: <角色> run=<运行 ID>` trailer；实现提交带 `Implemented-by: <角色>`。所有提交可能是同一个 git 作者，gardener 靠这两个 trailer 区分角色。
- 一行从 `Shipped` 退回 `Partial` 或更低，在同一次提交里写明原因，不删除原记录。
- 不能用删掉「怎么确认」里某个入口的办法让一行升级：删入口算改验收，同样要单独提交并引用用户原话或 ADR。

## 维护

- **改变用户可见行为的那次提交，同时改它的那一行。** 不留到之后的清理提交。新能力、状态变化、发现某条声称是假的，都在当次提交里改。参考 Google SRE 的定义，凡是用户看得见的变化都算发布，都要有对应的行。
- 新增的命令 ID、菜单项、偏好键、entitlement、声明的 UTType，必须出现在描述它的那一行，不能挂在无关的行上凑数（见「门禁」）。
- **区域审查**：每个区域在下面的审查表里有最近一次审查的日期和审查人。超过 30 天未审查、且这期间该区域有代码改动的，下一次合入前先审查（相当于 OpenAI 的 doc-gardening，定期清理过时文档）。
- 一次审查追加一个带日期的小节，不覆盖旧小节，结尾写「这次没有检查什么」。

## 门禁

`npm run ledger:check` 的五条规则门禁仍在计划中。实现后，它会作为 CI 和合入前检查的一项，检查：

1. 状态、验证两格都在枚举里；`Partial` 有 `限制：`；`Shipped` 的验证是 `真机` 且链接了 `docs/validation/`；
2. ID 不重复；计划一格的工作包 ID 在开发计划里存在；
3. 每个路径都能解析到文件；没有行号、计数和构建产物路径；`Absent` 的位置是 `—`；
4. App 声明的每个名字都出现在某一行：CommandRouter 的命令 ID、菜单项 identifier、`DisplayPreferences` 的键、entitlements、`Info.plist` 声明的 UTType；
5. 同一次提交里，某行状态升级的同时改写了「怎么确认」中的验收本身，报出来交给审查；只追加或修改「限制：」文本不报。

它**不能**判断一句话是不是真的：路径存在不代表那条行为还在。这需要真机复验和区域审查来补。

在 `ledger:check` 实现之前，合入审查时按上面五条人工核对。

`docs/feature-ledger.html` 是本文件的渲染视图，可按状态、阶段筛选和搜索，**由本文件生成，不要手改**。
每次提交改动本文件时，都在同一个提交里运行 `npm run ledger:build` 并提交生成的 HTML；CI 运行
`npm run ledger:html-check`，拒绝过时的 HTML。`ledger:check` 仍是迁移计划 A12 的后续工作。

## 发布门槛怎么读

不单独维护一份发布清单，直接按「计划」一列筛选：

- **MVP（v0.0.1）**：计划为 P0–P3 的行，全部是 `Shipped`，或 `Partial` 且限制已被用户接受（引用原话）；
- **首发 v1**：计划为 P0–P6 的行，同样要求；格式类的行未达标时，从对外支持声明里删掉，而不是保留一个 `Partial`。

---

## Part 1 — picsee 现在有什么

### 打开与输入

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| OPEN-01 | 首次打开空态 | Partial | 单元 | P1-02、P1-07 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageStatus.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/`、`App/CanvasWindowController.swift` | 冷启动、没有打开过文件夹：显示 21 页空态，有“选择文件夹”按钮和拖入提示；底部搜索、排序、信息、显示按钮为禁用。⌘O 可选单张图片或文件夹。限制：搜索/排序/显示待 P3；@1x 普通空态、既有启动路径与拖入提示见[记录](validation/P1.md#p1-07空态加载失败取消菜单焦点与中英文本)；#92 r6 签名像素确认宽/窄布局及完整英文提示（[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；从未打开文件夹的真正冷启动、中文签名像素、加载/取消未验。 |
| OPEN-02 | 打开面板 | Partial | 无 | P0-09、P1-02 | `App/PicseeApp.swift`、`App/Commands/CommandMenu.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift` | ⌘O 选一张图或一个目录，画布显示该图；在面板里取消，当前状态不变。限制：File › Open…、⌘O（图片与目录）、取消与不支持文件的提示已 @1x 真机通过（[记录](validation/P1.md#p1-02finder打开面板拖入与输入失败)）；底部 Open… 按钮仅单元。 |
| OPEN-03 | 从 Finder 打开 | Partial | 单元 | P1-02 | `App/Info.plist`、`App/PicseeApp.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Input/`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift` | 在 Finder 对一张 JPEG 用“打开方式 → picsee”，App 启动并显示该图。限制：Finder“打开方式”与双击（rank `Alternate`，需设为默认程序）未验；`open -a` 多文件成集合、按名称 ←/→、不回绕、Esc 无变化 @1x 通过（[记录](validation/P1.md#p1-02finder打开面板拖入与输入失败)）。 |
| OPEN-04 | 拖入打开 | Partial | 单元 | P1-02 | `Packages/PicseeKit/Sources/PicseeApplication/Input/`、`Packages/PicseeKit/Sources/PicseeMacUI/Input/`、`App/CanvasWindowController.swift` | 从 Finder 拖一张图进窗口，显示该图；拖入不支持的文件给出明确提示，当前图不变。限制：#73 修复后 @1x 合成拖入通过：未打开过的图片、ZIP、文件夹与多文件夹提示、多图成集合（[记录](validation/P1.md#p1-02finder打开面板拖入与输入失败)）；真实鼠标未验；无拖入高亮。 |
| OPEN-05 | 无法读取的图片 | Partial | 单元 | P1-07、P2-03 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageStatus.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerRetryIntent.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/`、`App/CanvasWindowController.swift` | 打开截断的 JPEG：显示 25 页错误态，有“重试”和“下一张”；底部工具仍可用，可经网格按钮或 Esc 返回；不会显示上一张图。限制：网格与 Esc 返回待 P3-01；@1x 损坏/截断说明和 Retry 见[记录](validation/P1.md#p1-07空态加载失败取消菜单焦点与中英文本)；#92 r4 签名像素确认错误图标、构图及窄窗无碰撞（[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；截断 JPEG、加载中未验。 |
| OPEN-06 | 最近打开 | Partial | 单元 | P2-09、P3-14 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/RecentFolderStore.swift`、`App/Access/AccessMenus.swift`、`App/CanvasWindowController.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessRecovery.swift` | 打开一个目录后退出重开，最近列表里有它；授权失效时显示重新授权入口；不保存图片副本。限制：重启后浏览、随改名更新、运行中目录消失首次即提示重连 @1x 通过（[记录](validation/P2.md#p2-01授权根存储重连与租约)）；仅文件夹、最多 10 项；不保存图片副本未验；损坏库降级仅单元。 |
| OPEN-07 | 从剪贴板打开 | Absent | 无 | P4-02 | — | 截图到剪贴板后选“从剪贴板打开”，新窗口显示该图 |

### 查看与画布

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| VIEW-01 | 适应窗口 | Partial | 单元 | P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasPlacement.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 分别打开横图和竖图，都完整居中显示；拖动改窗口大小，图随之适应。限制：不超过 1× 适应、1× 时对齐 backing 网格；三入口与改窗口后重新适应 @1x 真机通过（[记录](validation/P1.md#运行-20261023-114600-view-01-04-05-minip1-0337mac-mini-1x)）；显式重开回到 fit；P1-08 的全尺寸内容窗口（适应区含标题栏条带）与比例指示器入口真机未验；@2x 未验。 |
| VIEW-02 | 实际像素 1:1 | Partial | 单元 | P0-03、P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 按 1，在 2× 屏上一个图像像素对应一个物理像素；窗口拖到 1× 外接屏后仍是 1:1（27 页）。限制：P0-03 的 `1` 键在 [@2x](validation/P0.md#p0-03画布真机验收7view-02--view-03)、[@1x](validation/P0.md#p0-03画布真机验收-1x7view-02--view-03mac-mini) 已验；actualPixels 的路由 1/菜单/按钮真机未验；跨屏拖窗、中文和 VoiceOver 未验；多文件仅显示首个。 |
| VIEW-03 | 以光标为锚点缩放 | Partial | 单元 | P0-03、P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 触控板捏合或按 +/−，光标下的那个像素始终停在光标下。限制：zoomIn/zoomOut：P0-03 的 +/− 在 [@2x](validation/P0.md#p0-03画布真机验收7view-02--view-03)、[@1x](validation/P0.md#p0-03画布真机验收-1x7view-02--view-03mac-mini) 已验；捏合、完整 VoiceOver 未验；现按键路由/菜单/按钮真机未验；按钮或指针在面板/画布外时以中心缩放，锚点选择已单测。 |
| VIEW-04 | 平移与边界 | Partial | 单元 | P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 放大后拖动，图像不会被拖出可见范围；回到适应窗口后位置复原（27 页）；限制：四向边界与 0 复原 @1x 真机通过（合成拖动，[记录](validation/P1.md#运行-20261023-114600-view-01-04-05-minip1-0337mac-mini-1x)）；真实鼠标/触控板拖动与 @2x 未验。 |
| VIEW-05 | 全屏 | Partial | 单元 | P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift` | ⌃⌘F 进入和退出全屏，当前图和缩放状态保持；限制：⌃⌘F 进出、适应重算 @1x 真机通过（[记录](validation/P1.md#运行-20261023-114600-view-01-04-05-minip1-0337mac-mini-1x)）；实际像素/自定义缩放下全屏、菜单与绿色按钮入口、@2x 未验。 |
| VIEW-06 | 按 EXIF 方向显示 | Partial | 单元 | P0-05、P1-03 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageIOPipeline.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 打开 S1 素材里八种 Orientation 的样本，全部正向显示；限制：@1x 真机方向 1–8 通过（[P0-05/06 记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)）；@2x 未验 |
| VIEW-07 | 透明图 | Partial | 单元 | P0-05 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageIOPipeline.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 打开透明 PNG，透明区域按背景设置显示，不是黑色；限制：@1x 真机不发黑（[记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)）；尚无背景设置；@2x 未验 |
| VIEW-08 | 大图不卡界面 | Partial | 单元 | P0-05、P1-04 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/DecodeAdmission.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/ImagePipeline.swift`、`Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasDecodePolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/FirstPreviewTracing.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 打开 48MP 图：加载期间窗口能拖、菜单能开；先出预览再变清晰；限制：@1x 真机先预览再清晰（日志）、加载中经辅助功能移动窗口可响应（[记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)）；鼠标拖动与菜单未验；48MP 以 45.4MP 代替；@2x 未验；该记录早于 P1-03 的重请求细节改动（同尺寸重装、缩放与全屏时），该重请求路径真机未验；P1-04 合入后 `4bdd6ef` @1x 重验先预览再清晰、小于视口的源图仍解非预览档、加载中经辅助功能移动窗口可响应（[P1 记录](validation/P1.md#p1-04渐进细节与位深资源上限)）；渐进档位（含预览覆盖视口或源图更小时仍请求首个非预览档，小于请求尺寸的细节返回不重复请求）、位深（含 16 位灰度）成本与资源上限仅单元证明；无关授权意图更新后的修订重试与细节受限续租仅纯单测证明，原生 opener 接线未真机验。 |
| VIEW-09 | 快速切图不串图 | Partial | 单元 | P1-05 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift` | 快速打开 A→B→C，让 A 最后才解码完：画布、标题、Inspector 都只显示 C；限制：“A 最后完成”单元通过；@1x 自然时序仅见一次（[记录](validation/P1.md#p1-04渐进细节与位深资源上限)），无延迟钩子、@2x 未验；标题/Inspector 仅文件名。同代次修订仅重试一次，清旧像素回 opening、关闭/失败清理及 #58 消耗重试后的延迟旧查找均单测；本修复真机未验。 |
| VIEW-10 | 上一张 / 下一张 | Partial | 单元 | P2-03 | `Packages/PicseeKit/Sources/PicseeApplication/Access/FolderNavigation.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderSnapshotNavigation.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/ViewerSessionNavigationHost.swift`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift` | ←/→ 按目录顺序翻图；到首尾时按设置停止或循环。限制：按键/菜单/按钮 Finder 顺序、首尾停止 @1x 真机通过（[记录](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)）；底部工具组按钮真机未验；P2-03 的循环、筛选及排序导航仅单元证明，原生菜单尚未接入、真机未验；扫描中按快照翻图，到已知末尾仍可按但不动，未枚举时按键合并为最后方向（P2-02，单元）。 |

### C 沉浸界面

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CHROME-01 | 工具自动隐藏 | Partial | 单元 | P1-08 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift` | 不动鼠标约 2.5 秒，底部三组工具和窗口红绿灯一起消失；隐藏后 Tab 聚焦不到、VoiceOver 读不到它们（13 页）。限制：@1x 隐藏后 AX 只剩画布见[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)，#92 r5 签名像素确认紧凑深色静态隐藏外观；隐藏时 Tab/命中排除仅单元，VoiceOver、@2x 未验。 |
| CHROME-02 | 唤回工具 | Partial | 单元 | P1-08 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerChromeHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift`、`App/ChromeAdapters.swift` | 鼠标移到底边或按 Tab，工具出现；移到顶部，红绿灯出现；按 Tab 时先唤回、再聚焦第一个控件（14 页）。限制：@1x 底边/顶边/Tab 唤回及窄窗不重叠通过（合成指针，[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；#92 r4 签名像素确认浅深面板尺寸/轮廓与完整短名；真实鼠标、@2x 未验。 |
| CHROME-03 | 操作中不隐藏 | Partial | 单元 | P1-08 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerChromeState.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift` | 打开菜单、拖动控件、Inspector 或 Filmstrip 展开时工具不消失；结束后重新计时。限制：@1x 菜单、Inspector、键盘焦点锁与点击后回画布通过（[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；#92 r4 签名像素确认工具布局；拖动、Filmstrip、@2x 未验。 |
| CHROME-04 | 工具常驻 | Partial | 单元 | P1-08、P3-11 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/DisplayPreferences.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Commands/CommandMenu.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Preferences/UserDefaultsDisplayPreferencesStore.swift` | 开启“始终显示工具”，工具不再隐藏；退出重开后设置仍在。限制：@1x 常驻开关及重开保持通过（[记录](validation/P1.md#p1-09外观与显示偏好)）；#92 r4 签名像素确认工具布局；窗口间同步仅单元、显示面板待 P3-11、@2x 未验。 |
| CHROME-05 | Esc 返回来源 | Partial | 单元 | P1-08、P3-01 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorFocus.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift` | 从网格进入的大图按 Esc 回到网格；单独打开的图按 Esc 不会出现一个不存在的网格。限制：@1x 单张图 Esc 无网格、工具焦点 Esc 回画布（[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；网格来源待 P3-01。 |
| CHROME-06 | 固定窗口与全屏光标 | Absent | 无 | P4-03 | — | 全屏不动鼠标，光标随工具一起隐藏；固定窗口模式下窗口大小不随图片改变 |

### 外观与显示偏好

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| PREF-01 | 跟随系统 / 浅色 / 深色 | Partial | 单元 | P1-09 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/DisplayPreferences.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/DesignSystem/Appearance/WindowAppearanceAdapter.swift`、`App/Commands/CommandMenu.swift` | 默认跟随系统，系统外观切换时窗口即时变化；手动选深色后不再跟随（11/12 页）。限制：系统外观实时切换仅单元证明（真机需用户切换系统设置）；手动浅/深即时切换与深色重开保持 @1x 真机通过（[记录](validation/P1.md#p1-09外观与显示偏好)）；浅色重开未验；@2x 未验。 |
| PREF-02 | 减少动态效果 | Partial | 单元 | P1-09 | `Packages/PicseeKit/Sources/PicseeMacUI/DesignSystem/Appearance/MotionPolicy.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift` | 打开系统“减少动态效果”，工具显隐和面板切换没有动画。限制：工具显隐与面板切换本身无动画；组件过渡随系统开关为 0（单元）；系统开关真机未验（用户步骤）。 |
| PREF-03 | 显示设置 | Absent | 无 | P3-11 | — | 15 页：点底部右侧“显示”按钮弹出面板，调缩略图大小、显示文件名、填充裁剪 / 完整显示、外观、始终显示大图工具，立即生效，退出重开仍保留 |
| PREF-04 | 偏好在窗口间同步 | Partial | 单元 | P1-09、P4-01 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Preferences/UserDefaultsDisplayPreferencesStore.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/DesignSystem/Appearance/WindowAppearanceAdapter.swift` | 开两个窗口，在一个里改主题、Filmstrip 显隐或工具常驻，另一个窗口即时同步（ADR-002）。限制：两窗口同步仅单元证明；App 目前只开一个窗口（P4-01）；Filmstrip 尚不存在（P2-06）。 |

### 文件夹浏览

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| FOLDER-01 | 边扫描边浏览 | Partial | 单元 | P2-02 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FolderBrowser/`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/`、`Packages/PicseeKit/Sources/PicseeCore/Models/`、`Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerStateHost.swift`、`App/CanvasWindowController.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/FolderScanning.swift` | 打开 S2（5000 项）：扫描时显示 24 页读取状态，可取消；扫描完成后显示按名称排第一的图片并可翻图（时间见 `docs/validation/P2.md`）。限制：仅单层（需 P2-04）；扫描中顺序临时；读取页后无扫描状态与取消（P2-09）；按名称首张、24 页读取与取消真机未验（[@1x 记录](validation/P2.md#p2-02分批扫描取消与快照导航)）。 |
| FOLDER-02 | 排序 | Partial | 单元 | P2-03 | `Packages/PicseeKit/Sources/PicseeCore/Models/FolderViewPolicy.swift`、`Packages/PicseeKit/Sources/PicseeCore/Models/FolderSnapshot.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/FolderBrowser/FolderBrowser.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderScanCoordinator.swift` | 按名称自然排序（img2 排在 img10 前）、修改日期、类型、大小，升降序都能切换 限制：Core 投影、扫描元数据与会话导航有单元证据；原生菜单尚未接入，真机未验。 |
| FOLDER-03 | 扩展名过滤 | Partial | 单元 | P2-03 | `Packages/PicseeKit/Sources/PicseeCore/Models/FolderViewPolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderScanCoordinator.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerStateHost.swift` | 只勾选 PNG，列表与翻图都只剩 PNG；取消过滤后恢复，当前图合理保留 限制：过滤、保留当前项、无匹配清除与晚到批次仅单元证明；原生菜单尚未接入，真机未验。 |
| FOLDER-04 | 子目录递归 | Absent | 无 | P2-04 | — | 打开递归，嵌套目录的图片出现；含循环符号链接的目录扫描能结束，不重复列出 |
| FOLDER-05 | 扫描进度 | Absent | 无 | P2-04、P2-09 | — | 还不知道总数时只显示“读取中”，不显示百分比；完成后显示真实数量 |
| FOLDER-06 | 按拍摄日期 / 像素尺寸排序 | Absent | 无 | P2-05 | — | 选按拍摄日期排序，元数据没读完时显示“排序未完成”，读完后顺序稳定 |
| FOLDER-07 | 外部变化同步 | Absent | 无 | P2-07、P2-08 | — | 在 Finder 里新增、删除、重命名图片，停止操作后列表很快一致；当前图被删时有明确的下一张 |
| FOLDER-08 | 空文件夹 | Absent | 无 | P2-08 | — | 打开空目录显示 22 页空态，可“选择其他文件夹”；侧栏和底部工具仍可用 |
| FOLDER-09 | 卷被卸载 | Absent | 无 | P2-08 | — | 浏览外接盘时推出它，显示不可用状态，不崩溃；重新挂载后可以重新打开 |

### Filmstrip

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| FILM-01 | 展开 / 收起 | Absent | 无 | P2-06 | — | 默认收起；展开后只有一组翻图按钮和序号，画布不变小；退出重开保持上次状态（33 页） |
| FILM-02 | 点选跳转 | Absent | 无 | P2-06 | — | 点一张缩略图跳到该图；翻图时当前项自动滚到可见位置；切换目录后不再显示旧目录的缩略图 |

### 网格、选择与菜单

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| GRID-01 | 网格浏览 | Absent | 无 | P3-01、P3-10 | — | 打开目录显示 11/12 页网格：紧凑标题、底部工具，没有顶部横幅；文件名单行显示 |
| GRID-02 | 网格与大图来回切换 | Absent | 无 | P3-01 | — | 选中一张按 Space 或 Enter 看大图，按 Esc 回网格，选择、当前项和滚动位置都恢复 |
| GRID-03 | 快速滚动不串图 | Absent | 无 | P3-02 | — | 在 S2 里快速来回滚动，每个格子的图和文件名始终对得上 |
| GRID-04 | 多选 | Absent | 无 | P3-09 | — | ⌘点击切换单项，Shift 点击从锚点选一段；计数正确，当前项与选择集合分开显示（32 页） |
| GRID-05 | 多选后的预览范围 | Absent | 无 | P3-09 | — | 选 3 张按 Space，翻图只在这 3 张内；Esc 回来后仍是这 3 张被选中 |
| GRID-06 | 目录侧栏 | Absent | 无 | P3-10 | — | 侧栏可拖宽、可收起，从左下角入口重新打开；退出重开保留宽度 |
| GRID-07 | 搜索与清除 | Absent | 无 | P3-10 | — | ⌘F 在“搜索当前文件夹”里按文件名搜索；无结果时显示 23 页，点“清除搜索”后内容恢复，当前项合理 |
| GRID-08 | 小窗口布局 | Absent | 无 | P3-10 | — | 窗口缩到 800×680，侧栏、工具、长文件名都不重叠（29 页） |
| GRID-09 | 图片右键菜单 | Absent | 无 | P3-12 | — | 右键显示快速查看、在访达中显示、拷贝路径、收藏、图片信息五项；能用键盘操作，Esc 关闭后焦点回到原处（31 页） |
| GRID-10 | 在访达中显示 | Absent | 无 | P3-12 | — | 右键选“在访达中显示”，Finder 打开并选中该文件 |
| GRID-11 | 拷贝路径 | Absent | 无 | P3-12 | — | 右键选“拷贝路径”，粘贴到文本编辑出现该文件的完整路径 |
| GRID-12 | 收藏 | Absent | 无 | P3-14 | — | 收藏后缩略图左上角出现心形标记，侧栏“个人收藏”里能找到；文件被移走后显示“找不到”，不显示错图 |
| GRID-14 | 子文件夹树 | Absent | 无 | P3-10 | — | 侧栏里当前文件夹下列出子文件夹和各自数量，点子文件夹只浏览它；数量未知时不显示数字 |
| GRID-15 | 添加多个文件夹 | Absent | 无 | P3-15、P2-01 | — | 用“添加文件夹”加入第二个文件夹，两者都在侧栏，退出重开仍在；不复制任何图片 |
| GRID-16 | 所有照片汇总 | Absent | 无 | P3-15 | — | 点“所有照片”看到已加入的全部文件夹的图片；其中一个授权失效时只少掉它的图片，并提示重新授权 |
| GRID-17 | 最近查看 | Absent | 无 | P3-14 | — | 看过几张图后，侧栏“最近查看”按时间列出它们；文件被移走后显示“找不到” |
| GRID-13 | 自适应 / 瀑布流布局 | Absent | 无 | P7-06 | — | 切到瀑布流，混合长宽比的图片按原比例排列，当前选中项不跳走 |

### 信息与元数据

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| INFO-01 | 基础 Inspector | Absent | 无 | P3-13 | — | ⌘I 打开右侧面板：缩略图、文件名、尺寸、类型、日期、大小和“加入个人收藏”；浅深色同一面板（16/34 页）；读不到的值显示“未知” |
| INFO-02 | 切图后信息不过期 | Absent | 无 | P3-13 | — | Inspector 开着快速翻图，面板始终只显示当前这张的信息 |
| INFO-03 | 拍摄参数、GPS、IPTC | Absent | 无 | P5-01 | — | 打开带 EXIF 的照片，Inspector 显示镜头、光圈、快门、GPS；没有这些数据的图不显示假值 |
| INFO-04 | Finder 标签 | Absent | 无 | P5-02 | — | 给图片设一个颜色标签，Finder 里看到同样的标签；按标签过滤只剩该标签的图 |

### 授权与文件访问

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| ACCESS-01 | 单文件打开后的目录授权入口 | Partial | 单元 | P0-04 | `Packages/PicseeKit/Sources/PicseeApplication/Access/FolderNavigation.swift`、`App/Access/FolderGrantPrompt.swift`、`App/CanvasWindowController.swift` | 在 sandbox 版本里只打开一张图，按 → 时提示授权所在目录，不会静默失败。限制：→/← 提示、面板授权、不匹配提示 @1x 真机通过（[记录](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)）；AppKit 接线无单元 UI 证据。 |
| ACCESS-02 | 目录授权跨重启保留 | Partial | 单元 | P0-04、P2-01 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/`、`App/Resources/Picsee.entitlements`、`docs/adr/0008-folder-access-read-only-app-scoped-bookmarks.md` | 授权一个目录，退出重开后直接可浏览，不再弹授权。限制：重启、跨签名重建、重复授权同根与重连后重启均 @1x 直接浏览（[P0](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)、[P2](validation/P2.md#p2-01授权根存储重连与租约)）；损坏库仅单元；`com.apple.security.files.bookmarks.app-scope`，保持只读。 |
| ACCESS-03 | 失效授权的修复 | Partial | 单元 | P2-01 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/FileAccess.swift`、`Packages/PicseeKit/Sources/PicseeCore/Access/FileAccessPort.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessRecovery.swift`、`App/Access/ReconnectPrompt.swift`、`App/Access/AccessServices.swift`、`App/CanvasWindowController.swift` | 授权目录找不到（被删除或所在卷不可用）后打开最近项，提示重新连接；重新选择后恢复浏览。目录被移动或改名时，最近项直接在新位置浏览。限制：@1x 删除后最近项弹 26 页重连，重选恢复且根 ID 不变；改名后直接浏览不提示（[记录](validation/P2.md#p2-01授权根存储重连与租约)）；跨目录移动、删后重建、废纸篓为实现者观察，卷不可用未验。 |
| ACCESS-04 | 权限被撤销 | Absent | 无 | P2-08 | — | 浏览中撤销目录访问，显示 26 页提示并可重新授权；不会从缓存里继续显示原图 |
| ACCESS-05 | 访问范围用完即释放 | Partial | 单元 | P0-04 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/FileAccess.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessImageSource.swift`、`App/CanvasWindowController.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift` | 打开再关闭授权目录的窗口，诊断日志显示访问范围已释放（方法见 `docs/validation/P0.md`）。限制：关窗日志 `remaining=0 outcome=released` @1x 真机通过（[P0](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)、[P1-04](validation/P1.md#p1-04渐进细节与位深资源上限)）；日志不区分临时/租约；续租/租约平衡、P2-02 扫描租约释放仅单元。 |

### 缓存与资源

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CACHE-01 | 内存占用有上限 | Partial | 单元 | P1-06、P3-06 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageMemoryCache.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageIOPipeline.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/MemoryPressurePolicy.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ResourceSnapshotTracing.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/ImagePresentationPinning.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`App/PicseeApp.swift`、`App/UntestedResourceAdapters.swift` | 连续浏览 S2 三轮，内存不持续增长；两个窗口共用同一个上限（数据见 `docs/validation/P3.md`）。限制：仅内存缓存；@1x 重开命中、截断图不入缓存（[记录](validation/P1.md#p1-06内存成本与最小有界缓存)）；无磁盘缓存/预取，压力/S2/两窗口未验。#58 重叠修订在原租约内最多复核一次源文件，旧查找及消耗重试后的当前修订交付仅自动化通过；本修复真机未验。 |
| CACHE-02 | 缩略图磁盘缓存 | Absent | 无 | P3-03、P3-04 | — | 第二次打开同一目录，网格明显更快出图；手动删掉缓存目录后自动重建，原图不受影响 |
| CACHE-03 | 清理缓存 | Absent | 无 | P3-05、P3-07 | — | 设置里显示缓存占用，点清理后占用归零，正在进行的旧任务不会把缓存重新写回 |
| CACHE-04 | 本地诊断面板 | Absent | 无 | P3-07 | — | 打开诊断面板，看到本地的解码数、队列长度、缓存命中；不上传任何数据 |

### 命令与键盘

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CMD-01 | 基础快捷键 | Partial | 单元 | P0-09 | `Packages/PicseeKit/Sources/PicseeCore/Commands/`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/CommandRouter.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Commands/CommandMenu.swift`、`App/CanvasWindowController.swift`、`App/UI/InspectorPlaceholder.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ChromeWindowCommands.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift` | Space、←/→、Esc、Enter、0/1、+/−、⌘F、⌘O、⌘I 在菜单、按钮和键盘上触发的是同一个动作；未实现的不在菜单里显示快捷键。限制：preview/enter/search 未实现；菜单/按键/占位按钮与 File › Close、⌘W @1x 真机一致；工具组按钮仅合成点击。 |
| CMD-02 | 输入框和菜单优先 | Partial | 单元 | P0-09 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/CommandRouter.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Commands/CommandMenu.swift`、`App/Commands/CommandWindow.swift` | 在搜索框里按 Space 或 ←，只编辑文字不翻图；菜单打开时按 Esc 只关菜单。限制：输入框是占位字段，不是搜索；字段裸键（含打开目录后的 ←/→）、Edit 菜单与菜单 Esc 已 @1x 真机通过；非画布窗口裸键未验。 |
| CMD-03 | 自定义快捷键 | Absent | 无 | P4-04 | — | 在设置里改一个快捷键，立即生效；与已有快捷键冲突时提示 |
| CMD-04 | 鼠标与触控板预设 | Absent | 无 | P4-04 | — | 切换滚轮为“翻图”或“缩放”，行为随之改变；不影响文本框里的选区和系统手势 |
| CMD-05 | 全局快捷键 | Absent | 无 | P7-09 | — | App 在后台时按全局快捷键，picsee 被唤到前台 |

### 窗口与桌面工具

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| WIN-01 | 多窗口 | Absent | 无 | P4-01 | — | 开 3 个查看窗口，菜单命令只作用于最前面的窗口；关掉一个不影响另一个窗口正在加载的同一张图 |
| WIN-02 | 窗口置顶与透明度 | Absent | 无 | P4-02 | — | 开启置顶后切到别的 App，picsee 窗口仍在最上层；透明度可调 |
| WIN-03 | 图片 pin | Absent | 无 | P4-02 | — | 把当前图钉到桌面，pin 窗口无边框、可缩放、可调阴影和透明度 |
| WIN-04 | 文本 pin | Absent | 无 | P4-02 | — | 复制一段文字后新建文本 pin，内容正确显示并可置顶 |
| WIN-05 | 幻灯片 | Absent | 无 | P4-05 | — | 开始幻灯片，按设置的间隔、循环或随机播放；可暂停和继续；解码慢时不会越积越多 |
| WIN-06 | 缩略导航图 | Absent | 无 | P4-06 | — | 放大长图时出现缩略导航图，点击可跳到对应位置；不放大时不出现 |
| WIN-07 | pin 跨重启保留 | Absent | 无 | P7-09 | — | 留着两个 pin 退出 App，重开后两个 pin 回到原位置 |

### 编辑与导出

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| EDIT-01 | 旋转与翻转 | Absent | 无 | P5-03 | — | 左转、右转、水平翻转、垂直翻转后画面正确；可以撤销和重做 |
| EDIT-02 | 裁剪 | Absent | 无 | P5-03 | — | 自由裁剪和固定比例裁剪；在旋转后的图上裁剪，导出结果与屏幕上的选框一致 |
| EDIT-03 | 导出另存 | Absent | 无 | P5-04 | — | 导出为 JPEG 或 PNG，可选尺寸和质量；透明 PNG 不变黑；选去除元数据后导出文件里没有 GPS；替换一个已存在的其他文件时取消或写入失败，旧文件保持完整；不能选源文件作为目标 |
| EDIT-04 | 复制图片、分享、打印、用其他 App 打开 | Absent | 无 | P5-05 | — | 复制图片后能粘贴到预览；系统分享面板、打印面板、“打开方式”菜单都能正常调出 |
| EDIT-05 | 移到废纸篓 | Absent | 无 | P5-06 | — | 删除一张图后它出现在废纸篓里；不存在永久删除选项 |
| EDIT-06 | 未保存编辑的提示 | Absent | 无 | P5-07 | — | 裁剪后不保存就切图或关窗口，提示保存、放弃或取消；选取消后编辑仍在 |

### 格式

格式行以 P6-01 的格式能力矩阵为准；未通过的格式从对外支持声明中删掉。

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| FMT-01 | JPEG、PNG、HEIC、TIFF | Partial | 单元 | P0-05、P6-01 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageIOPipeline.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/DecodeBudget.swift`、`Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasDecodePolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift` | 打开 S1 素材里这四种格式，颜色、方向、透明都正确；限制：@1x 真机四种格式显示正确（目视，[记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)）；S1 素材集未完整；颜色未测量；@2x 未验 |
| FMT-02 | GIF 动画 | Absent | 无 | P6-02 | — | 打开动画 GIF 正常播放；切走后停止播放、不再占用 CPU |
| FMT-03 | PDF 分页 | Absent | 无 | P6-02 | — | 打开多页 PDF，可以翻页，页码显示正确 |
| FMT-04 | 系统可读的 RAW | Absent | 无 | P6-03 | — | 打开 S4 里的 RAW 样本：能显示的标明是完整解码还是只显示内嵌预览；不能显示的给出明确提示 |
| FMT-05 | WebP、SVG、PSD 等扩展格式 | Absent | 无 | P6-01、P7-07 | — | 每种格式标明完整解码、只显示首帧或系统预览；SVG 里的脚本不会被执行 |
| FMT-06 | LibRaw 增强 RAW | Absent | 无 | P7-03 | — | 打开系统不支持的相机 RAW，按格式矩阵里声明的相机型号逐个通过 |
| FMT-07 | HDR 显示 | Absent | 无 | P7-04 | — | 在 HDR 屏上打开 HDR 照片显示高亮细节；拖到 SDR 屏后正常显示，不过曝 |
| FMT-08 | 超大图切片显示 | Absent | 无 | P7-08 | — | 打开超出分辨率上限的地图类大图，放大后逐步变清晰，内存不超过预算 |

### 可访问性与本地化

MVP 起就是门槛（见计划 P3「MVP 还需检查」），P6-04 补全全部路径。

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| A11Y-01 | VoiceOver | Absent | 无 | P3-10、P6-04 | — | 开 VoiceOver 走一遍打开→网格→大图→Inspector，每个控件都有正确的名称，隐藏的工具不被读出 |
| A11Y-02 | 纯键盘操作 | Partial | 单元 | P0-09、P6-04 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorFocus.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift` | 不碰鼠标完成打开目录、选图、看大图、返回、打开 Inspector；焦点始终可见（28 页）。限制：选图/网格待 P3；⌘O 选目录、占位面板焦点 @1x 真机通过；空态状态按钮 Tab/Esc @1x 通过（[记录](validation/P1.md#p1-07空态加载失败取消菜单焦点与中英文本)）；失败态焦点环未验。 |
| A11Y-03 | 对比度与焦点不被遮挡 | Absent | 无 | P6-04 | — | 浅色和深色下文字与控件对比度符合 `design/DESIGN.md` 的目标；获得焦点的控件不被其他元素挡住 |
| A11Y-04 | 中英文界面 | Partial | 单元 | P1-07、P6-04 | `App/Resources/Localizable.xcstrings`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/`、`Packages/PicseeKit/Tests/PicseeMacUITests/ViewerLocalizationTests.swift` | 系统语言切到中文或英文，界面文字跟随变化，没有截断和未翻译的键名。限制：中文目录、空态/错误态局部布局与图标名称仅单元；系统语言切换、中文签名像素未验；全界面截断检查待 P6-04。 |

### 分发

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| DIST-01 | 签名与公证 | Absent | 无 | P6-06 | — | 在另一台 Mac 上下载安装包后直接打开，Gatekeeper 不拦截；`spctl --assess` 通过 |
| DIST-02 | 全新环境可用 | Absent | 无 | P6-05 | — | 新建一个 macOS 用户首次打开，没有旧授权和缓存也能正常使用；损坏的缓存数据库能自动恢复 |
| DIST-03 | 安装包内容干净 | Absent | 无 | P6-07 | — | 检查 `.app` 内容，没有 REA、研究素材、私人照片或开发路径 |
| DIST-04 | 升级保留数据 | Absent | 无 | P6-08 | — | 用新版本覆盖旧版本，设置、收藏和目录授权都还在 |
| DIST-05 | 自动更新 | Absent | 无 | P6-08 | — | 有新版本时 App 提示更新，更新后签名校验通过 |
| DIST-06 | App 图标 | Partial | 无 | P1-10 | `App/Resources/Assets.xcassets/AppIcon.appiconset/`、`project.yml` | 在 Dock、访达（列表与图标视图）和 ⌘Tab 里看到 Lens 图标，浅色/深色下 16–512 pt 都清晰无白边。限制：@1x Dock 与访达列表/图标视图通过（[记录](validation/P1.md#p1-10app-图标)）；⌘Tab、浅色 Dock、@2x 未验；无 Icon Composer `.icon`。 |

### 增强

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| EXT-01 | 识别并复制图中文字 | Absent | 无 | P7-01 | — | 打开含文字的截图，选中文字复制，粘贴结果正确；缩放、旋转或翻图后选区不错位 |
| EXT-02 | 提取主体 | Absent | 无 | P7-02 | — | 对人像提取主体，复制后粘贴为带透明背景的图；换一张图后不会沿用上一张的结果 |
| EXT-03 | 跟随 Finder 排序 | Absent | 无 | P7-05 | — | 在 Finder 里手动排好顺序后用 picsee 打开该目录，翻图顺序与 Finder 一致；读不到时回到默认排序并提示 |

### 不做

这些是计划里明确不做或延期的事。移到这里的行保留原 ID，写明谁在什么时候决定的；以后要做，先改计划再挪回 Part 1。

| ID | 能力 | 决定 | 来源 |
|---|---|---|---|
| — | 覆盖原文件保存 | v1 不做，需先完成冲突检测和原子替换验证 | 计划 §7、[ADR-007](adr/0007-save-as-by-default-no-overwrite-in-v1.md) |
| — | GIF、PDF、RAW 的编辑写回 | v1 不做 | 计划 §7 |
| — | 永久删除、批量导出和批量删除 | 不做；基础多选不等于批量资产管理 | 计划 §1.0、§9 |
| — | Windows、iOS、账号、云同步、语义搜图、插件、复杂调色 | 不在计划内 | 计划 §9 |
| — | Pro、订阅、购买恢复 | 暂缓，付费模式未定 | 计划 §1.0 |
| — | 与 Picview 十种窗口模式逐项一致 | 不追求 | 计划 §6 |

---

## Part 2 — 环境差异

picsee 只支持 macOS，没有跨平台差异表，但同一能力在不同硬件和系统上可能表现不同。这里记录**只在部分环境验证过**的情况；表里没有的能力，默认指已在下表“基准”环境验证。

| 环境 | 基准 | 状态 |
|---|---|---|
| 显示器 | Mac mini 本地 1× 屏 + MacBook Retina @2x 屏（@2x 验收从 mini 经 SSH 执行） | Mac mini @1x 已测（P0-03、P0-09、P0-05/06）；MacBook @2x 已测（P0-03，本地运行）；经 SSH 的 @2x 未配置 |
| 系统 | macOS 14（最低部署版本）与当前正式版 | 建账时均未测 |
| 芯片 | Apple Silicon | Intel 为 `Unknown`，未验证前不声明支持 |
| 机器 | Mac mini（本地、唯一的本地真机测试机）与 MacBook（仅 @2x；经 SSH 时命令须进入其桌面启动的 tmux 会话） | Mac mini @1x 已测（P0-03、P0-09、P0-05/06）；MacBook @2x 已测（P0-03，本地运行）；经 SSH 的 @2x 未配置 |

某项能力在某个环境下行为不同，在本节加一行：`| <ID> | <环境> | <状态> | <差异与 validation 链接> |`。

## Part 3 — 区域审查

| 区域 | 最近审查 | 审查人 | 备注 |
|---|---|---|---|
| 打开与输入 | 2026-10-24 | doc-gardener | #92 UI 对照（c9504fe..94f67c2）：OPEN-01/05 已记录空态/错误态布局及签名像素的有限证据，保持 Partial/单元；OPEN-02/03/04 输入路由不变。 前次记录：P2-02 分批扫描（#78，p2/p2-02-folder-browser，6435bba..a0fbe5a）：打开目录改为分批扫描、首批前显示 24 页读取态；OPEN-01/02/04/05/06 验收不受影响（空态、失败态、最近列表写入时机与过滤规则不变）。上次：P2-01 真机记录（docs/p2-01-device-mini，1c28a09..e8de551，run 20261024-074141-P2-01-ACCESS-02-03-OPEN-06） |
| 查看与画布 | 2026-10-24 | doc-gardener | #58 最新 main 复核（430e2a2..9a230ce）：VIEW-09 已注明消耗单次重试后的延迟旧查找仅单测、本修复真机未验；验收、状态与既有未验条件保留。VIEW-06/07 的方向和透明解码不变。上次：#92 UI 对照（c9504fe..94f67c2），VIEW-10 只改底部布局与文件名宽度，翻图路由不变。 |
| C 沉浸界面 | 2026-10-24 | doc-gardener | #92 UI 对照（c9504fe..94f67c2）：CHROME-01…04 已补布局/静态显隐证据，未升级；CHROME-05 返回路由不变。 前次记录：P2-02 分批扫描（#78，p2/p2-02-folder-browser，6435bba..a0fbe5a）：`ViewerSession` 只改上一张/下一张启用与路由，不改 chrome 显隐；CHROME-01…05 不变。上次：P2-01 授权根重连（#77，p2/p2-01-access，d703ede..c5c9738） |
| 外观与显示偏好 | 2026-10-24 | doc-gardener | #92 UI 对照（c9504fe..94f67c2）：面板颜色、轮廓与阴影变化不改 PREF-02 的 Reduce Motion 策略或显隐动画。 前次记录：P2-02 分批扫描（#78，p2/p2-02-folder-browser，6435bba..a0fbe5a）：`CanvasWindowController` 只接扫描与读取态；PREF-02 不变。上次：P1-02 输入（#70，p1/p1-02-inputs，2044bef..defbf44） |
| 文件夹浏览 | 2026-10-24 | doc-gardener | #92 UI 对照（c9504fe..94f67c2）：ViewerStateHost 只为 empty/failed 增加组合布局，FOLDER-01 的读取状态与取消路径不变。 前次记录：打开文件夹按名称首张（#82，fix/folder-open-first-by-name，d2fbd1a..1f76c23）：fa06a0a 只删限制「首张取自首批」；0ec1d04 单独改验收并引用用户 2026-10-24 原话；状态 `Partial`/`单元` 不变；代码在扫描完成后取 `completed.entries.first`（按名称排序）。1f76c23 按提议在限制补「按名称首张…真机未验」，因链接的 @1x 记录显示旧行为 `img-0040`；P2.md 无计时，「时间见」暂无数字；能力名「边扫描边浏览」现只合以图片打开。上次：P2-02 真机记录（docs/p2-02-device-mini，3b69d7e..5e83132，run 20261024-092410-P2-02-FOLDER-01-VIEW-10） |
| Filmstrip | 2026-10-23 | doc-gardener | P1-09 外观与偏好（#50，p1/p1-09-appearance-prefs，736fa1a..6eb5dc2）：`filmstripExpanded` 现随 `displayPreferences.v1` 持久化，仍无 Filmstrip UI；FILM-01 保持 `Absent`。上次：P0-09 Session（#11/#29，dcfe3f8..bef71d5） |
| 网格、选择与菜单 | 2026-10-24 | doc-gardener | P2-02 真机记录（docs/p2-02-device-mini，3b69d7e..5e83132）：5e83132 引用 P2-01，GRID-15 计划含 P2-01，但范围只改文档、无代码；GRID-15 保持 `Absent`。上次：P0-09 Session（#11/#29，dcfe3f8..bef71d5） |
| 信息与元数据 | 2026-10-23 | doc-gardener | P1-04/P1-05 加载路径（#41，p1/p1-04-load-path，30c2f06..afc18f2）：Inspector 占位面板只加当前已接受图片的文件名行（`inspector.item-name`，属 VIEW-09 验收），无其他文件信息；INFO-01 保持 `Absent`。上次：P0-09（#10，749697a..7054a5d） |
| 授权与文件访问 | 2026-10-24 | doc-gardener | 限制缩写（chore/kimi-trial-low，fe5125d..45e2fea）：只改 ACCESS-05 限制，状态 `Partial`/`单元` 与验收不变；P0、P1-04 记录链接保留，「日志不区分临时/租约」「续租/租约平衡、P2-02 扫描租约释放仅单元」保留；删去的 `4bdd6ef`／关闭按钮细节仍在 P1-04 记录第 6 步。上次：P2-02 真机记录（docs/p2-02-device-mini，3b69d7e..5e83132） |
| 缓存与资源 | 2026-10-24 | doc-gardener | #58 最新 main 复核（430e2a2..9a230ce）：CACHE-01 已记录重叠修订在原租约内最多复核一次源文件，保留 Partial/单元、本修复真机未验及压力/S2/两窗口限制；新增测试覆盖旧查找与已消耗重试的交付，未升级能力。上次：P1-07（fa2703f..d97615d），仅公开 fileURL。 |
| 命令与键盘 | 2026-10-24 | doc-gardener | #92 UI 对照（c9504fe..94f67c2）：CMD-01 的命令集合、路由和启用条件不变；仅底部工具尺寸与排列变化。 前次记录：限制缩写（chore/kimi-trial-low，fe5125d..45e2fea）：只改 CMD-01 限制，状态与验收不变；未实现项与「工具组按钮仅合成点击」保留；删去的 P1-07 句是通过记录而非限制，证据仍在 P1 记录 P1-07 节。上次：P2-02 分批扫描（#78，p2/p2-02-folder-browser，6435bba..a0fbe5a） |
| 窗口与桌面工具 | 2026-10-22 | doc-gardener | P7-09 去掉自动更新，WIN-07 不受影响 |
| 编辑与导出 | 2026-10-22 | doc-gardener | EDIT-03 验收按 ADR-007 补替换与源文件拒绝，状态未变；EDIT-05 依赖 P5-04 写权限；「不做」里覆盖原文件一行的来源已补 ADR-007，决定与状态未变 |
| 格式 | 2026-10-24 | doc-gardener | #58 最新 main 复核（430e2a2..9a230ce）：ImageIOPipeline 只新增观察冲突后的文件头复核，支持格式、方向与颜色解码不变；FMT-01 保留既有状态及 @1x 记录，@2x 未验。上次：P1-07（fa2703f..d97615d），解码器与格式集合未改。 |
| 可访问性与本地化 | 2026-10-24 | doc-gardener | #92 UI 对照（c9504fe..94f67c2）：A11Y-04 的“中文仅由目录覆盖测试证明”待 owner 更新为目录及局部布局单元证据；系统中文签名像素与全界面截断仍未验。 前次记录：P2-02 分批扫描（#78，p2/p2-02-folder-browser，6435bba..a0fbe5a）：新增 3 条读取页字符串（Reading Folder…、说明、Cancel Reading），均有 en、zh-Hans，ViewerLocalizationTests 覆盖；A11Y-04 不变；A11Y-02 读取页 Cancel 键盘可达未验。上次：P2-01 授权根重连（#77，p2/p2-01-access，d703ede..c5c9738） |
| 分发 | 2026-10-23 | doc-gardener | P1-10 真机记录（validation/p1-10-device-mini，3996845..08c5ecf，run 20261023-212346-P1-10-DIST-06）：DIST-06 只改「限制：」（@1x Dock 与访达列表/图标视图通过），仍 `Partial`/`无`，验收不变；⌘Tab、浅色 Dock、@2x 未验。DIST-01…05 不变。上次：App 图标 Lens（feat/app-icon-lens，cfef98f..75127a2） |
| 增强 | 2026-10-21 | 建账 | 同上 |

### 2026-10-21 建账

依据开发计划 v0.2 的 P0–P7 工作包、1.0 节功能对应表和 1.3 节 20 页 mockup 映射，逐项建行。

这次没有检查什么：没有对照 Picview 实际运行逐项核对（Picview 功能见 `docs/PICVIEW_FEATURES.md`，只是静态资源证据）；没有对照 FastStone 调研报告补行；没有用户可见能力的工作包不单独建行：P0-01、P0-02、P0-06、P0-07（工程与技术验证）、P0-08（原生设计映射，体现在各 UI 行）、P1-01（身份与错误模型）、P3-08（规模验证，结果进 `docs/validation/P3.md`）。

### 2026-10-24 #92 已交付 UI 对照（c9504fe..94f67c2）

复核打开、画布、沉浸工具、偏好、文件夹读取、命令与本地化区域；六条 UI 行仅更新限制，状态与验收未变。A11Y-04 的中文证据说明需 owner 修正。

这次没有检查什么：未运行测试、构建或 App，未复测原始像素与交互；设备记录只覆盖其中列出的 @1x 入口，不代表整行验收通过。

### 2026-10-24 #58 缓存观察冲突审查

范围 `f478834..271e579`：VIEW-09、CACHE-01 仅追加限制与测试说明，仍为 `Partial` / `单元`；验收前缀保持不变。两行单元格分别约 392、234 字，需 owner 压缩限制，不能删去尚未验证的入口或条件。VIEW-06、VIEW-07、FMT-01 因管线路径被映射，但对应方向、透明和格式行为未改；引用的 P0/P1 记录仍存在。

这次没有检查什么：未运行测试、App 构建或真机；未读取审计报告或 PR 评论；未验证性能、内存压力、S2／两窗口及 @2x；生成器同步检查不代表行为验收。

### 2026-10-24 #58 限制缩写复核

范围 `f478834..2d1cfd0`：owner 仅压缩 VIEW-09、CACHE-01 的限制，分别约 170、163 个可见字符（两句、三句）；原提议已解决。两行仍 `Partial` / `单元`，验收前缀与既有证据链接不变；自然时序不可稳定复现、@2x、标题/Inspector 仅文件名、一次重试及清理、仅内存缓存、压力/S2/两窗口和本修复真机未验均保留。实现代码相对 `271e579` 未变，HTML 同步检查通过。

这次没有检查什么：未运行测试、构建或真机，未读取审计材料；不把限制缩写视作新增行为证据。

### 2026-10-24 #58 在最新 main 上复核（430e2a2..9a230ce）

VIEW-09、CACHE-01 的限制与当前代码和回归测试范围一致，状态/验证仍为 Partial/单元；逐提交核对验收前缀未变。VIEW-06、VIEW-07、FMT-01 因 ImageIOPipeline 路径映射纳入，方向、透明与格式行为未改；既有 P0/P1 验证链接存在并包含对应 ID。未发现新增的命令、菜单、偏好、entitlement 或 UTType 声明；没有能力升级。

这次没有检查什么：未运行测试、App 构建或真机，未读取审计报告或 PR 评论；不把源码与回归测试阅读视为运行通过证据，@2x、性能、压力/S2/两窗口及本修复真机仍未验。

## 参考做法

- Anthropic，[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)：一开始就写出完整功能列表、全部标为未通过；每项带测试步骤；agent 只能改“是否通过”，不能删改测试；必须端到端验证后才能标为通过。对应本账簿的「先写好的验收」和「防止验收被悄悄放宽」。
- OpenAI，[Harness engineering](https://openai.com/index/harness-engineering/)：仓库里的文档是唯一可信的来源；AGENTS.md 只做目录，指向更深的文档；有一份按产品区域和架构层打分、跟踪缺口的质量文档，以及定期扫描过时文档的 doc-gardening agent。对应「区域审查」，以及 AGENTS.md 只链接本账簿、不复制内容。
- OpenAI Cookbook，[Using PLANS.md](https://developers.openai.com/cookbook/articles/codex_exec_plans)：计划是活文档，写给对项目毫无了解的读者。对应「怎么确认」必须是任何人都能照着做的操作。
- Google SRE，[Reliable Product Launches](https://sre.google/sre-book/reliable-product-launches/) 与 [Launch Coordination Checklist](https://sre.google/sre-book/launch-checklist/)：用户可见的变化都算发布；清单里每一项都要能说明为什么需要，每条操作都要具体可行；清单定期复审。对应「维护」和「发布门槛怎么读」。
- Meta，[Holistic Configuration Management at Facebook](https://blog.acolyer.org/2015/10/16/holistic-configuration-management-at-facebook/)（SOSP 2015）：新代码先以关闭状态上线，用 Gatekeeper 逐步放开；配置当作代码，由校验器自动检查不变量。对应「功能开关后面的能力」和门禁的机器检查。
- NASA 系统工程的需求验证矩阵（[NASA NTRS](https://ntrs.nasa.gov/api/citations/20160003166/downloads/20160003166.pdf)）：每条需求标明验证方法（测试、分析、检查、演示）。对应「验证」列。SpaceX 的“每条需求都要带上提出它的人的名字”（Isaacson《Elon Musk》）对应「计划」列：每行都能追溯到工作包和背后的用户决定。没有找到 SpaceX 公开的需求矩阵原文。
- mdpro 的 `docs/feature-ledger.md`：五值状态、`Partial` 必须写限制、路径从仓库根写、同一次提交更新行，都沿用；单元格长成修复史的问题，用 150 字上限和 validation 链接避免。
