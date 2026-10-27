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
| 怎么确认 | 一个在 App 里能做的操作和应看到的结果，不是“看代码”。列出几个入口，就是几个都要验（见「验证」）。**验收部分（「限制：」之前）不超过三句、约 150 字**；「限制：」之后的文字不计入这个长度，但每一句都要是事实（未验的入口、仅单元的范围、待哪个工作包）。过程、截图、日志与历史写进 `docs/validation/`，这里只放链接 |

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
| OPEN-01 | 首次打开空态 | Partial | 单元 | P1-02、P1-07 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageStatus.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/`、`App/CanvasWindowController.swift` | 冷启动、没有打开过文件夹：显示 21 页空态，有“选择文件夹”按钮和拖入提示；底部搜索、排序、信息、显示按钮为禁用。⌘O 可选单张图片或文件夹。限制：搜索/排序/显示待 P3；@1x 空态与拖入提示（[P1-07](validation/P1.md#p1-07空态加载失败取消菜单焦点与中英文本)）、#92 签名像素宽窄布局与英文（[#92](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）通过；真冷启动、中文像素、加载/取消未验。 |
| OPEN-02 | 打开面板 | Partial | 无 | P0-09、P1-02 | `App/PicseeApp.swift`、`App/Commands/CommandMenu.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift` | ⌘O 选一张图时画布显示该图，选一个目录时进入该目录网格；在面板里取消，当前状态不变。限制：选目录进网格仅单元（P3-01），签名真机未验；File › Open…、⌘O 选图、取消与不支持文件的提示已 @1x 真机通过（[记录](validation/P1.md#p1-02finder打开面板拖入与输入失败)）；底部 Open… 按钮仅单元。 |
| OPEN-03 | 从 Finder 打开 | Partial | 单元 | P1-02 | `App/Info.plist`、`App/PicseeApp.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Input/`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift` | 在 Finder 对一张 JPEG 用“打开方式 → picsee”，App 启动并显示该图。限制：Finder 打开方式与双击未验（rank `Alternate`）；`open -a` 多文件集合、←/→ 不回绕、未授权单图 Esc 无变化 @1x 通过（[记录](validation/P1.md#p1-02finder打开面板拖入与输入失败)）；授权目录内单图 Esc 回网格仅单元（P3-01）。 |
| OPEN-04 | 拖入打开 | Partial | 单元 | P1-02 | `Packages/PicseeKit/Sources/PicseeApplication/Input/`、`Packages/PicseeKit/Sources/PicseeMacUI/Input/`、`App/CanvasWindowController.swift` | 从 Finder 拖一张图进窗口，显示该图；拖入不支持的文件给出明确提示，当前图不变。限制：#73 修复后 @1x 合成拖入通过：未打开过的图片、ZIP、文件夹与多文件夹提示、多图成集合（[记录](validation/P1.md#p1-02finder打开面板拖入与输入失败)）；拖入文件夹现进网格，仅单元（P3-01）；真实鼠标未验；无拖入高亮。 |
| OPEN-05 | 无法读取的图片 | Partial | 单元 | P1-07、P2-03 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageStatus.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerRetryIntent.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/`、`App/CanvasWindowController.swift` | 打开截断的 JPEG：显示 25 页错误态，有“重试”和“下一张”；底部工具仍可用，可经网格按钮或 Esc 返回；不会显示上一张图。限制：网格/Esc 仅单元（P3-01）；@1x 三类错误/重试（截断 PNG）与构图/窄窗通过（[P1](validation/P1.md#p1-07空态加载失败取消菜单焦点与中英文本)、[#92](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；JPEG/加载中未验；过滤后下一张与扫描中重试仅单元，原生组合未验。 |
| OPEN-06 | 最近打开 | Partial | 单元 | P2-09、P3-14 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/RecentFolderStore.swift`、`App/Access/AccessMenus.swift`、`App/CanvasWindowController.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessRecovery.swift` | 打开一个目录后退出重开，最近列表里有它；授权失效时显示重新授权入口；不保存图片副本。限制：重启后浏览、随改名更新、运行中目录消失后第一次 Open Recent 即提示重连 @1x 通过（[记录](validation/P2.md#p2-01授权根存储重连与租约)，早于 P2-07 监听，未复验）；窗口内正在看的目录被删时不弹重连，按 FOLDER-07 显示文件夹扫描失败与重试；最近目录重开现进网格，仅单元（P3-01）；仅文件夹、最多 10 项；不保存图片副本未验；损坏库降级仅单元。 |
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
| VIEW-08 | 大图不卡界面 | Partial | 单元 | P0-05、P1-04 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/DecodeAdmission.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/ImagePipeline.swift`、`Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasDecodePolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/FirstPreviewTracing.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 打开 48MP 图：加载期间窗口能拖、菜单能开；先出预览再变清晰；限制：@1x 预览→清晰及 AX 移窗可响应已验（[P0 记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)、[P1 记录](validation/P1.md#p1-04渐进细节与位深资源上限)）；48MP 用 45.4MP；鼠标拖窗/菜单、@2x 未验。渐进、位深/上限、重请求与重试仅单元，原生 opener 未验；合格源首预览可走磁盘缓存（见 CACHE-02）。 |
| VIEW-09 | 快速切图不串图 | Partial | 单元 | P1-05 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift` | 快速打开 A→B→C，让 A 最后才解码完：画布、标题、Inspector 都只显示 C；限制：“A 最后完成”单元通过；@1x 自然时序仅见一次（[记录](validation/P1.md#p1-04渐进细节与位深资源上限)），无延迟钩子、@2x 未验；标题/Inspector 仅文件名。同代次修订只重试一次；清旧像素回 opening、关闭/失败清理及 #58 消耗重试后的延迟旧查找、#122 迟到旧 pin/旧观察与取消均仅单测，#122 与网格内快速翻图真机未验。 |
| VIEW-10 | 上一张 / 下一张 | Partial | 单元 | P2-03 | `Packages/PicseeKit/Sources/PicseeApplication/Access/FolderNavigation.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderSnapshotNavigation.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/ViewerSessionNavigationHost.swift`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`；菜单 ID：`folder.loop.menu` | ←/→ 按目录顺序翻图；到首尾时按设置停止或循环。限制：既有按键/菜单/按钮顺序及首尾停止 @1x 通过（[记录](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)）；工具按钮未验；P2-03 循环/筛选/排序、P2-04 递归快照重建与扫描中快照、末端、方向合并仅单元，原生组合未验。P3-01 冻结预览集首尾停止，不读循环设置，新增路径未验。 |

### C 沉浸界面

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CHROME-01 | 工具自动隐藏 | Partial | 单元 | P1-08 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift` | 不动鼠标约 2.5 秒，底部三组工具和窗口红绿灯一起消失；隐藏后 Tab 聚焦不到、VoiceOver 读不到它们（13 页）。限制：@1x 隐藏后 AX 只剩画布见[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)，#92 r5 签名像素确认紧凑深色静态隐藏外观；隐藏时 Tab/命中排除仅单元，VoiceOver、@2x 未验。 |
| CHROME-02 | 唤回工具 | Partial | 单元 | P1-08 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerChromeHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift`、`App/ChromeAdapters.swift` | 鼠标移到底边或按 Tab，工具出现；移到顶部，红绿灯出现；按 Tab 时先唤回、再聚焦第一个控件（14 页）。限制：@1x 底边/顶边/Tab 唤回及窄窗不重叠通过（合成指针，[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；#92 r4 签名像素确认浅深面板尺寸/轮廓与完整短名；真实鼠标、@2x 未验。 |
| CHROME-03 | 操作中不隐藏 | Partial | 单元 | P1-08 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerChromeState.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift` | 打开菜单、拖动控件、Inspector 或 Filmstrip 展开时工具不消失；结束后重新计时。限制：@1x 菜单、Inspector、键盘焦点锁与点击后回画布通过（[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）；#92 r4 签名像素确认工具布局；拖动、Filmstrip、@2x 未验。 |
| CHROME-04 | 工具常驻 | Partial | 单元 | P1-08、P3-11 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/DisplayPreferences.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Commands/CommandMenu.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Preferences/UserDefaultsDisplayPreferencesStore.swift` | 开启“始终显示工具”，工具不再隐藏；退出重开后设置仍在。限制：@1x 常驻开关及重开保持通过（[记录](validation/P1.md#p1-09外观与显示偏好)）；#92 r4 签名像素确认工具布局；窗口间同步仅单元、显示面板待 P3-11、@2x 未验。 |
| CHROME-05 | Esc 返回来源 | Partial | 单元 | P1-08、P3-01 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorFocus.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift` | 从网格进入的大图按 Esc 回到网格；单独打开的图，其文件夹已授权时 Esc 回该文件夹网格，否则不会出现一个不存在的网格。限制：网格来源与单图回网格仅单元（P3-01），签名原生组合未验；单张图（File Grant）Esc 无网格、工具焦点 Esc 回画布 @1x 已验（[记录](validation/P1.md#p1-08c-沉浸工具与窗口-chrome)）。 |
| CHROME-06 | 固定窗口与全屏光标 | Absent | 无 | P4-03 | — | 全屏不动鼠标，光标随工具一起隐藏；固定窗口模式下窗口大小不随图片改变 |

### 外观与显示偏好

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| PREF-01 | 跟随系统 / 浅色 / 深色 | Partial | 单元 | P1-09 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/DisplayPreferences.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/DesignSystem/Appearance/WindowAppearanceAdapter.swift`、`App/Commands/CommandMenu.swift` | 默认跟随系统，系统外观切换时窗口即时变化；手动选深色后不再跟随（11/12 页）。限制：系统外观实时切换仅单元证明（真机需用户切换系统设置）；手动浅/深即时切换与深色重开保持 @1x 真机通过（[记录](validation/P1.md#p1-09外观与显示偏好)）；浅色重开未验；@2x 未验。 |
| PREF-02 | 减少动态效果 | Partial | 单元 | P1-09 | `Packages/PicseeKit/Sources/PicseeMacUI/DesignSystem/Appearance/MotionPolicy.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift` | 打开系统“减少动态效果”，工具显隐和面板切换没有动画。限制：工具显隐与面板切换本身无动画；组件过渡随系统开关为 0（单元）；系统开关真机未验（用户步骤）。 |
| PREF-03 | 显示设置 | Absent | 无 | P3-11 | — | 15 页：点底部右侧“显示”按钮弹出面板，调缩略图大小、显示文件名、填充裁剪 / 完整显示、外观、始终显示大图工具，立即生效，退出重开仍保留 |
| PREF-04 | 偏好在窗口间同步 | Partial | 单元 | P1-09、P4-01 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Preferences/UserDefaultsDisplayPreferencesStore.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/DesignSystem/Appearance/WindowAppearanceAdapter.swift` | 开两个窗口，在一个里改主题、Filmstrip 显隐或工具常驻，另一个窗口即时同步（ADR-002）。限制：两窗口同步仅单元证明；文件夹排序字段与方向也经 DisplayPreferences 在窗口间同步，仅单元（#124）；App 目前只开一个窗口（P4-01）；Filmstrip 尚不存在（P2-06）。 |

### 文件夹浏览

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| FOLDER-01 | 扫描后进入网格 | Partial | 单元 | P2-02 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FolderBrowser/`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/`、`Packages/PicseeKit/Sources/PicseeCore/Models/`、`Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerStateHost.swift`、`App/CanvasWindowController.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/FolderScanning.swift` | 打开 S2（5000 项）：扫描中显示 24 页读取状态，取消回到上一状态；完成后出网格，排序首张为当前项，Space 进大图可翻图。限制：网格入口、读取状态与取消恢复仅单元（P3-01）；递归开关/边界与计数仅单元（P2-04）；网格中切换递归重扫时的读取状态、取消回到原网格与失败 Retry 仅单元（P2-04）；读取状态在网格外壳主列内（侧栏打开时位于其旁）显示仅单元（P3-10）；读后状态待 P2-09；读取/取消/首张当前项真机未验（[@1x 记录](validation/P2.md#p2-02分批扫描取消与快照导航)；耗时未测）；所看目录的监听静默刷新（保留排序、筛选与当前项）见 FOLDER-07，仅单元。 |
| FOLDER-02 | 排序 | Partial | 单元 | P2-03 | `Packages/PicseeKit/Sources/PicseeCore/Models/FolderViewPolicy.swift`、`Packages/PicseeKit/Sources/PicseeCore/Models/FolderSnapshot.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/FolderBrowser/FolderBrowser.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderMenuPolicy.swift`、`App/Commands/CommandMenu.swift`；菜单 ID：`folder.sort.menu`、`folder.sort.name.menu`、`folder.sort.modificationDate.menu`、`folder.sort.type.menu`、`folder.sort.size.menu`、`folder.order.menu`、`folder.order.ascending.menu`、`folder.order.descending.menu` | 按名称自然排序（img2 排在 img10 前）、修改日期、类型、大小，升降序都能切换；所选排序各窗口共用，重启后仍在。限制：排序字段与方向经 DisplayPreferences 跨窗口、文件夹和启动保留，仅单元（#124）；取消读取采用当前 App 排序（P3-01，#124）；递归结果的排序（P2-04）、投影、元数据与菜单策略仅单元；底栏入口复用菜单条件与策略仅单元；拍摄日期与像素面积排序见 FOLDER-06；原生菜单、中文与辅助功能真机未验；所看目录的监听静默刷新（保留排序、筛选与当前项）见 FOLDER-07，仅单元。 |
| FOLDER-03 | 扩展名过滤 | Partial | 单元 | P2-03 | `Packages/PicseeKit/Sources/PicseeCore/Models/FolderViewPolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderScanCoordinator.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderMenuPolicy.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerStateHost.swift`、`App/Commands/CommandMenu.swift`；菜单 ID：`folder.extensions.menu`、`folder.extension.all.menu`、`folder.extension.none.menu`、`folder.extension.<lowercased-extension>.menu` | 只勾选 PNG，列表与翻图都只剩 PNG；取消过滤后恢复，当前图合理保留；同一文件夹重扫仍只看 PNG，打开别的文件夹时清空。限制：同文件夹重扫及单图打开前结束扫描后仍保留扩展名过滤，换文件夹清空，重启不恢复；同文件夹以解析符号链接后的路径判定，别名等非符号链接路径未验；仅单元（#124）；取消读取恢复过滤（P3-01）、保留当前项、无匹配须待扫描完成才呈现，筛选等待中失败显示 Retry，首个可用批次按当前排序选 Current、后续批次不移项；静默刷新保留旧无匹配并延迟新无匹配至完成，上述与取消、Retry、晚到批次及跨扩展名别名先过滤后选可用 URL 仅单元；浏览时筛选隐藏当前项，当前项移到最近的可见项，仅单元（P2-07）；原生菜单、无匹配状态与按钮真机未验。 |
| FOLDER-04 | 子目录递归 | Partial | 单元 | P2-04 | `Packages/PicseeKit/Sources/PicseeCore/Ports/FolderScanning.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/FolderBrowser/FolderBrowser.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderScanCoordinator.swift`、`App/Commands/CommandMenu.swift`、`App/CanvasWindowController.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/WindowImageTitle.swift`；菜单 ID：`folder.recursive.menu` | 打开递归，嵌套目录的图片出现；含循环符号链接的目录扫描能结束，不重复列出 限制：默认关闭且仅会话，取消后菜单保留勾选；10 万访问项保护只用于递归，平铺目录不受此新上限；边界/去重/代次、跨扩展名别名过滤、快速切换/Retry 清图与取消恢复仅单元；网格中切换递归按文件夹读取重扫，取消恢复原网格与原勾选，失败显示 Retry，仅单元，真机未验。打开图片时设置标题栏代理图标（representedURL）仅单元；普通空结果标题/AXDocument 清理 @1x 样本通过（[记录](validation/P2.md#p2-04递归浏览的空结果标题复验)）；本机 chmod 000 子目录错误与部分计数已测，沙盒权限未验；菜单勾选、真实循环链接、中英文 AX、@2x 未验；所看目录的监听静默刷新（保留排序、筛选与当前项）见 FOLDER-07，仅单元。 |
| FOLDER-05 | 扫描进度 | Partial | 单元 | P2-04、P2-09 | `Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderScanCoordinator.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageStatus.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerStateHost.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/ViewerChromeState.swift` | 还不知道总数时只显示“读取中”，不显示百分比；完成后显示真实数量 限制：目录读取/完成计数、错误时保留计数与重试仅单元；错误后仅可在已知图片中翻图，已有图的缩放命令可用；单图入口 Retry 保留当前图（含失败后翻到的图），之后按快照排序翻图；取消完整状态和 P2-09 最近打开未验。page24 整体对照 PENDING(P3-10)（2026-10-25 用户决定「先合入，page24 归 P3-10」）；既有侧栏、页脚与读取控制 @1x 对照 FAIL（[记录](validation/P2.md#p2-04递归浏览的空结果标题复验)）；其他签名真机条件及 @2x 未验；所看目录的监听静默刷新（保留排序、筛选与当前项）见 FOLDER-07，仅单元。 |
| FOLDER-06 | 按拍摄日期 / 像素尺寸排序 | Partial | 单元 | P2-05 | `Packages/PicseeKit/Sources/PicseeCore/Models/FolderViewPolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderScanCoordinator.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageFolderMetadataReader.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridBrowserView.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift`；菜单 ID：`folder.sort.captureDate.menu`、`folder.sort.pixelDimensions.menu`；状态 ID：`folder.sort.pending`、`folder.sort.incomplete` | 选按拍摄日期排序，元数据没读完时显示“排序未完成”，读完后顺序稳定 限制：按需租约、旧代次丢弃、缺失值末尾与面积溢出安全、真实 ImageIO 头信息、菜单策略、非阻塞状态及 #108 同步头信息读取移离 Swift cooperative executor 仅单元；监听刷新保留未变项元数据、仅为新增或变更项读头与失败后保留已读值仅单元；缺失或读取失败时显示“部分排序元数据无法读取”，未知值排末尾；拍摄日期无时区信息按 UTC 解析，TIFF DateTime 回退可能是文件软件修改时间；排序字段与方向跨窗口、文件夹和启动保留，仅单元（#124）；原生菜单、中文、辅助功能、签名真机与 @2x 未验。 |
| FOLDER-07 | 外部变化同步 | Partial | 单元 | P2-07、P2-08 | `Packages/PicseeKit/Sources/PicseeCore/Ports/FolderWatching.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Watching/`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderScanCoordinator.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderEntryRestore.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Access/AccessServices.swift`、`App/CanvasWindowController.swift`、`App/PicseeApp.swift` | 在 Finder 里新增、删除、重命名图片，停止操作后列表很快一致；当前图被删时有明确的下一张 限制：每个授权根一个共享监听、合并（静默 200 ms、最长 1 s）、丢事件与回到前台全量重扫、当前项移到后继仅单元与临时目录 FSEvents 测试；所看目录下隐藏项与包内的变化不触发重扫；监听建立失败（授权或 FSEvents 拒绝）时不假装在监听，该窗口只在回到前台时重扫并重新订阅（App 接线未测）；后台刷新失败（含所看目录被删除或移走）时显示文件夹扫描失败与重试、保留旧列表，当前图文件已不存在则清除，目录回来后下一次变化自动恢复，跟随移走的目录属 P2-08；重命名按删除加新增处理，保留身份属 P2-08；浏览时筛选隐藏当前项，当前项同样移到最近的可见项；元数据排序下刷新保留未变项、仅读新增或变更项，仅单元；每次变化全量重扫所看目录；App 目前只开一个窗口，多窗口共享仅单元；刷新删除已选项时选择只收缩、被删项缩略图请求取消，可见缩略图按新快照重新请求，仅单元；2 s 目标只在假时钟上测了从事件到快照的等待，扫描耗时不计；网格文件名搜索时的监听刷新保留搜索词、筛选结果、计数与无结果页（见 GRID-07），仅单元；不在原导航顺序中的当前项（如被过滤排除的单图输入）静默刷新后移到首张可见图，无专门测试；签名沙盒真机、5000 项目录的扫描耗时与真实 2 s 未测。 |
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
| GRID-01 | 网格浏览 | Partial | 单元 | P3-01、P3-10 | `Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderGridProjection.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridBrowserView.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridShellView.swift`、`App/CanvasWindowController.swift` | 打开目录显示 11/12 页网格：紧凑标题、底部工具，没有顶部横幅；文件名单行显示。限制：快照、cell 复用、响应式几何（含 legacy/overlay 滚动条、浮点整列边界与实际 cell 帧）、缩略图装载、缩略图选择描边、文件名末尾截断、当前项环、常驻标题栏与浅深底块仅单元；侧栏/底栏框架、搜索与排序入口仅单元（P3-10）；信息待 P3-13、显示待 P3-11，收藏待 P3-14；监听触发的静默刷新不进入读取状态、保留当前项，仅单元（P2-07），刷新后滚动位置是否保持未测；签名真机、@2x、VoiceOver、中英文未验。 |
| GRID-02 | 网格与大图来回切换 | Partial | 单元 | P3-01 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/FolderGridProjection.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridViewerPresentation.swift`、`App/CanvasWindowController.swift` | 选中一张按 Space 或 Enter 看大图，按 Esc 回网格，选择、当前项和滚动位置都恢复。限制：连续方向键后单一选择、滚动条宽度变化及浮点整列边界的方向键列步长、选择/当前项/滚动恢复、预览中删除、单图 Esc 顺序、取消读取恢复，以及侧栏显隐或宽度变化后的网格列数与滚动恢复仅单元（App 接线无测试）；原生按键、像素、VoiceOver、中英文未验；多选的选择与当前项恢复由 P3-09 单元覆盖（App 接线无测试），签名 App 全链路待验；所看目录的监听静默刷新（保留排序、筛选与当前项）见 FOLDER-07，仅单元。 |
| GRID-03 | 快速滚动不串图 | Partial | 单元 | P3-02 | `Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridBrowserView.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridThumbnailScheduler.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessImageSource.swift`、`App/CanvasWindowController.swift` | 在 S2 里快速来回滚动，每个格子的图和文件名始终对得上。限制：可见区及邻近两行请求、复用/换目录/隐藏取消、身份/修订/倍率校验、失败回放与有限重试、可见优先级、授权缓存接线仅单元；S2 真机快滚、@2x 像素、签名沙盒与视觉对照未验。 |
| GRID-04 | 多选 | Partial | 单元 | P3-09 | `Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridBrowserView.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/BrowserSelection.swift`、`App/CanvasWindowController.swift` | ⌘点击切换单项，Shift 点击从锚点选一段；计数正确，当前项与选择集合分开显示（32 页）。限制：原生选择与模型同步、缩略图 cell 重载后的选择绘制有单元覆盖；外部删除已选项时选择只收缩、不并入当前项，仅单元（P2-07）；32 页底栏计数属于 P3-10，签名 App 像素对照、VoiceOver 与真机手势待验。 |
| GRID-05 | 多选后的预览范围 | Partial | 单元 | P3-09 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/PreviewSet.swift`、`App/CanvasWindowController.swift` | 选 3 张按 Space，翻图只在这 3 张内；Esc 回来后仍是这 3 张被选中。限制：冻结范围、删除扣除与 Esc 来源恢复有单元覆盖；签名 App 全链路待验。 |
| GRID-06 | 目录侧栏 | Partial | 单元 | P3-10 | `Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridShellView.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/DisplayPreferences.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Preferences/UserDefaultsDisplayPreferencesStore.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift`；菜单 ID：`grid.sidebar.toggle.menu`；偏好键：`gridSidebarWidth`、`gridSidebarVisible` | 侧栏可拖宽、可收起，从左下角入口重新打开；退出重开保留宽度。限制：160–320 pt 拖拽、底栏入口、键盘/辅助功能调整与 UserDefaults 往返仅单元；菜单入口（⌃⌘S）仅构建；签名真机、@2x、VoiceOver 与中英文未验。 |
| GRID-07 | 搜索与清除 | Partial | 单元 | P3-10 | `Packages/PicseeKit/Sources/PicseeCore/Models/FolderSnapshot.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/GridSearchState.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Browser/GridSearchProjectionScheduler.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridShellView.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridViewerPresentation.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridWatchedSearchRefresh.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift`；菜单 ID：`grid.search.menu` | ⌘F 在“搜索当前文件夹”里按文件名搜索；无结果时显示 23 页，点“清除搜索”后内容恢复，当前项合理。限制：文件名匹配、当前项恢复、23 页无结果纵向位置、间距、字体与浅深配色及底栏浅深色布局、底栏 1280/800/480 pt 设计间距、图标展开/失焦收起/清除、长搜索词中间截断及排序入口仅单元；监听刷新保留搜索筛选、当前项按最近幸存项、搜索状态与无结果页，搜索后进大图 ←/→ 只在筛选结果内翻图，仅单元；App 接线与 ⌘F 菜单路由、签名真机、中文、VoiceOver 与像素对照未验。 |
| GRID-08 | 小窗口布局 | Partial | 单元 | P3-10 | `Packages/PicseeKit/Sources/PicseeMacUI/Grid/GridShellView.swift`、`Packages/PicseeKit/Tests/PicseeMacUITests/GridShellTests.swift`、`Packages/PicseeKit/Tests/PicseeMacUITests/GridFooterSearchTests.swift`、`App/CanvasWindowController.swift` | 窗口缩到 800×680，侧栏、工具、长文件名都不重叠（29 页）。限制：800×680 下侧栏、40 pt 底栏、主列内实际 cell 与单行文件名不重叠仅单元；底栏搜索与排序控件框架仅单元；信息/显示尚未加入；签名真机、@2x、VoiceOver 与中英文未验。 |
| GRID-09 | 图片右键菜单 | Absent | 无 | P3-12 | — | 右键显示快速查看、在访达中显示、拷贝路径、收藏、图片信息五项；能用键盘操作，Esc 关闭后焦点回到原处（31 页） |
| GRID-10 | 在访达中显示 | Absent | 无 | P3-12 | — | 右键选“在访达中显示”，Finder 打开并选中该文件 |
| GRID-11 | 拷贝路径 | Absent | 无 | P3-12 | — | 右键选“拷贝路径”，粘贴到文本编辑出现该文件的完整路径 |
| GRID-12 | 收藏 | Partial | 单元 | P3-14 | `Packages/PicseeKit/Sources/PicseeCore/Library/PersonalImages.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Library/`、`Packages/PicseeKit/Sources/PicseeApplication/Library/PersonalImageProjection.swift` | 收藏后缩略图左上角出现心形标记，侧栏“个人收藏”里能找到；文件被移走后显示“找不到”，不显示错图。限制：仅存储与模型（P3-14 切片 1，单元）：收藏按授权根与根内相对路径加文件号保存，重启后仍在；移走、删除、换成别的文件或目录时解析为“找不到”，授权根失效或其文件夹被删除时为不可用且每次重新检查、不用旧结果；不复制图片或缩略图，单图授权的图片不能收藏。心形标记、侧栏“个人收藏”与收藏操作均未接线（待 P3-10/P3-01 切片 2）；按文件号判断，外部编辑器原子保存后也会显示“找不到”，再次查看该图后恢复；删除后新建的文件若恰好复用同一文件号，可能被当作原图显示；签名沙盒与真机未验。 |
| GRID-14 | 子文件夹树 | Absent | 无 | P3-10 | — | 侧栏里当前文件夹下列出子文件夹和各自数量，点子文件夹只浏览它；数量未知时不显示数字 |
| GRID-15 | 添加多个文件夹 | Absent | 无 | P3-15、P2-01 | — | 用“添加文件夹”加入第二个文件夹，两者都在侧栏，退出重开仍在；不复制任何图片 |
| GRID-16 | 所有照片汇总 | Absent | 无 | P3-15 | — | 点“所有照片”看到已加入的全部文件夹的图片；其中一个授权失效时只少掉它的图片，并提示重新授权 |
| GRID-17 | 最近查看 | Partial | 单元 | P3-14 | `Packages/PicseeKit/Sources/PicseeCore/Library/PersonalImages.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Library/`、`Packages/PicseeKit/Sources/PicseeApplication/Library/PersonalImageProjection.swift` | 看过几张图后，侧栏“最近查看”按时间列出它们；文件被移走后显示“找不到”。限制：仅存储与模型（P3-14 切片 1，单元）：按查看时间从新到旧保存最多 50 张，重看移到最前，重启后保留；移走后解析为“找不到”；计数在全部解析前为空，之后只数可用项；与“最近打开”的文件夹分开保存，互不影响。查看图片尚未记录访问、侧栏“最近查看”未接线（待 P3-10/P3-01 切片 2）；签名沙盒与真机未验。 |
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
| ACCESS-03 | 失效授权的修复 | Partial | 单元 | P2-01 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/FileAccess.swift`、`Packages/PicseeKit/Sources/PicseeCore/Access/FileAccessPort.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessRecovery.swift`、`App/Access/ReconnectPrompt.swift`、`App/Access/AccessServices.swift`、`App/CanvasWindowController.swift` | 授权目录找不到（被删除或所在卷不可用）后打开最近项，提示重新连接；重新选择后恢复浏览。目录被移动或改名时，最近项直接在新位置浏览。限制：@1x 删除后弹 26 页重连、重选恢复同根、改名直接浏览（[记录](validation/P2.md#p2-01授权根存储重连与租约)）；重选后进网格仅单元（P3-01）；跨目录移动等仅实现者观察，卷不可用未验。 |
| ACCESS-04 | 权限被撤销 | Absent | 无 | P2-08 | — | 浏览中撤销目录访问，显示 26 页提示并可重新授权；不会从缓存里继续显示原图 |
| ACCESS-05 | 访问范围用完即释放 | Partial | 单元 | P0-04 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/FileAccess.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessImageSource.swift`、`App/CanvasWindowController.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Watching/WatchHub.swift` | 打开再关闭授权目录的窗口，诊断日志显示访问范围已释放（方法见 `docs/validation/P0.md`）。限制：关窗 `remaining=0 outcome=released` @1x 通过（[P0](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)、[P1-04](validation/P1.md#p1-04渐进细节与位深资源上限)）；日志不分临时/租约；续租、P2-02 扫描租约、P2-04 递归取消/失败租约释放、P3-01 单图回网格短租约与 P2-05 元数据按需读取的逐图租约释放仅单元，网格窗口关窗未真机验；P2-07 共享监听在有订阅期间持有该根的租约、最后一个订阅取消后释放，仅单元；关窗释放的真机记录早于 P2-07，有监听时未复验。 |

### 缓存与资源

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CACHE-01 | 内存占用有上限 | Partial | 单元 | P1-06、P3-06 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageMemoryCache.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageIOPipeline.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/MemoryPressurePolicy.swift`、`Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ResourceSnapshotTracing.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/ImagePresentationPinning.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`App/PicseeApp.swift`、`App/UntestedResourceAdapters.swift` | 连续浏览 S2 三轮，内存不持续增长；两个窗口共用同一个上限（数据见 `docs/validation/P3.md`）。限制：只衡量内存上限，磁盘缩略图已接线、见 CACHE-02。@1x 重开命中与截断图拒收已验（[P1 记录](validation/P1.md#p1-06内存成本与最小有界缓存)）；重叠修订一次复核、#122 迟到旧 pin/旧观察与取消票据仅单测；预取、压力/S2/两窗口与 #122 真机未验。 |
| CACHE-02 | 缩略图磁盘缓存 | Partial | 单元 | P3-03、P3-04 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ThumbnailDiskCache.swift`、`Packages/PicseeKit/Sources/PicseeCore/Identity/DurableThumbnailKey.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessImageSource.swift`、`App/PicseeApp.swift`、`App/CanvasWindowController.swift` | 第二次打开同一目录，网格明显更快出图；手动删掉缓存目录后自动重建，原图不受影响；限制：查看器首预览及网格≤1024px 已接线，网格接线仅单元；查看器重开命中（据无源解码推断）及方向3/6、透明 @1x 已验（[P3](validation/P3.md#p3-03--p3-04磁盘缩略图缓存命中查看器路径)），余仅单元；写入失败后隔次重试、拒绝符号链接缓存目录与按 generation 拦截读取仅单元（见 CACHE-03）；网格重开加速、手删重建、跨进程崩溃、P3-05/08、@2x 未验（ADR-009）。 |
| CACHE-03 | 清理缓存 | Partial | 单元 | P3-05、P3-07 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ThumbnailDiskCache.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/CacheMaintenance.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Cache/CacheSettingsModel.swift`、`App/UI/CacheSettingsWindow.swift`、`App/PicseeApp.swift`、`App/Commands/CommandMenu.swift`；菜单 ID：`settings.menu`（⌘,） | 设置里显示缓存占用，点清理后占用归零，正在进行的旧任务不会把缓存重新写回；限制：实测占用、跨实例 generation、清理、写入失败降级及读 lease 延迟删除有自动化测试；写入失败后跳过下一次写入尝试，再于后续尝试重试，持续失败时继续隔次重试且原图仍可显示；设置在租约释放后刷新，删除失败显示本地化原因并可重试。设置窗口和菜单未做签名真机验收，@1x/@2x 均未验。 |
| CACHE-04 | 本地诊断面板 | Absent | 无 | P3-07 | — | 打开诊断面板，看到本地的解码数、队列长度、缓存命中；不上传任何数据 |

### 命令与键盘

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CMD-01 | 基础快捷键 | Partial | 单元 | P0-09 | `Packages/PicseeKit/Sources/PicseeCore/Commands/`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/CommandRouter.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorEscapePolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Commands/CommandMenu.swift`、`App/CanvasWindowController.swift`、`App/UI/InspectorPlaceholder.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ChromeWindowCommands.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Chrome/ViewerChromeOverlay.swift`；菜单 ID：`command.preview.menu`、`command.enter.menu` | Space、←/→、Esc、Enter、0/1、+/−、⌘F、⌘O、⌘I 在菜单、按钮和键盘上触发的是同一个动作；未实现的不在菜单里显示快捷键。限制：preview/enter 接网格与菜单仅单元，search 的命令目录仅单元，⌘F 的网格 App 接线未验（查看态不可用）；既有菜单/按键/占位按钮与 ⌘W @1x 真机一致；新网格快捷键与焦点、Picsee › 设置…（⌘,）未验；按钮仅合成点击。 |
| CMD-02 | 输入框和菜单优先 | Partial | 单元 | P0-09 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/CommandRouter.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorEscapePolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Commands/CommandMenu.swift`、`App/Commands/CommandWindow.swift` | 在搜索框里按 Space 或 ←，只编辑文字不翻图；菜单打开时按 Esc 只关菜单。限制：Inspector 占位面板里的输入框是占位字段，不是搜索（网格底栏搜索见 GRID-07）；字段裸键（含打开目录后的 ←/→）、Edit 菜单与菜单 Esc 已 @1x 真机通过；非画布窗口裸键未验；P3-01 改 Esc 顺序与 Space/Enter 预览后未复验。 |
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
| A11Y-02 | 纯键盘操作 | Partial | 单元 | P0-09、P6-04 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorFocus.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift` | 不碰鼠标完成打开目录、选图、看大图、返回、打开 Inspector；焦点始终可见（28 页）。限制：网格键盘选图与 Esc 返回仅单元（P3-01）；读取态与网格中侧栏开关、宽度分隔条的 Tab 焦点仅单元（P3-10）；⌘O 选目录、占位面板焦点、空态按钮 Tab/Esc @1x 通过（[记录](validation/P1.md#p1-07空态加载失败取消菜单焦点与中英文本)）；失败态焦点环未验。 |
| A11Y-03 | 对比度与焦点不被遮挡 | Absent | 无 | P6-04 | — | 浅色和深色下文字与控件对比度符合 `design/DESIGN.md` 的目标；获得焦点的控件不被其他元素挡住 |
| A11Y-04 | 中英文界面 | Partial | 单元 | P1-07、P6-04 | `App/Resources/Localizable.xcstrings`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/States/`、`Packages/PicseeKit/Tests/PicseeMacUITests/ViewerLocalizationTests.swift` | 系统语言切到中文或英文，界面文字跟随变化，没有截断和未翻译的键名。限制：中文目录、空态/错误态局部布局与图标名称仅单元；侧栏“隐藏/显示/调整侧栏宽度”及缓存设置（设置、缩略图缓存、清理缓存、缓存失败提示）、网格缩略图失败占位「无法显示缩略图」及其 VoiceOver 标签中英文条目未上屏验证；系统语言切换、中文签名像素未验；全界面截断检查待 P6-04。 |

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
| 打开与输入 | 2026-10-27 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；OPEN-06 因 P2-09/P3-14 被映射，状态与验收未变。d87bdf1..83c1457（P3-03/04）：App/PicseeApp.swift 注入缩略图缓存；OPEN-02 验收于 7411cb0 按 ADR-0010 改写（目录进网格待 P3-01），状态与验证未变；OPEN-03 的打开结果、取消与 Finder 路径未变，缓存首预览见 CACHE-02。 gardener 复核（0cbd129..3d2fba3）：OPEN-02/05 限制已写明网格接线仅单元，验收未变；OPEN-04、OPEN-06、ACCESS-03 的文件夹拖入与最近项限制记录的是 P3-01 前的行为，目录现进网格，待 owner 处理（提议）；OPEN-03 的 Esc 无变化证据早于单图 Esc 改动，待 owner 确认。 gardener 复核（0cbd129..a3ec010）：OPEN-02/03/04/05/06、ACCESS-03 的网格接线限制已写明仅单元，「怎么确认」未变；OPEN-01 的空态与选图验收不涉及目录进网格，未变。 gardener 复核（0cbd129..a5c8c4a）：a3ec010 的 OPEN-01/05 压缩删去了 OPEN-05 的“截断 PNG”与“原生组合未验”（提议恢复）；OPEN-01 的“签名像素”限定也被删，本范围未改其行为，未提议。OPEN-02/03/04/06 的限制与代码一致。 gardener 复核（0cbd129..0d55474）：OPEN-02/04/06 的目录进网格、OPEN-03/05 的单图 Esc 与网格限制已写明仅单元；OPEN-01 仅 ViewerImageStatus 加 mode 守卫，空态未变。0d55474 恢复的限定与 a5c8c4a 相比验收前缀未变。无新增提议。 gardener 复核（4226e7c..e63bba7，2026-10-25）：OPEN-02…06 的网格接线与单图 Esc 限制已写明仅单元，怎么确认未改；OPEN-01 只改限制措辞，空态路径未变，状态与验证未变。OPEN-01、OPEN-03、OPEN-05 的怎么确认超过约 150 字，待 owner 压缩（PROPOSED）。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04 #102）：OPEN-01/02/04/05/06 路径触及的代码改动是窗口标题改由 WindowImageTitle 统一设置、文件夹扫描失败状态新增于 ViewerImageStatus；单图打开与解码失败路径未变，状态与验收未变。范围内 WindowImageTitle 还设置 representedURL（标题栏代理图标），无行命名该可见变化（提议 owner 决定写入 VIEW-09 或新行）。这次没有检查什么：真机标题栏与代理图标。 gardener 复核（1bebf9d..9442a18，2026-10-26）：OPEN-01/02/04/05/06 的 CanvasWindowController 改动只限网格壳与网格读取态布局，打开与拖入路径未变，状态与验收未变。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：OPEN-01/02/04/05/06 的 CanvasWindowController 改动（网格壳包裹、子视图层级、读取态焦点链）与 CommandMenu 新增菜单项只作用于网格，打开、拖入与取消路径未变，状态与验收未变；OPEN-01、OPEN-05 超约 150 字，既有，待 owner（PROPOSED）。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：OPEN-01/02/04/05/06 在哪含 CanvasWindowController.swift，该文件本次仅新增网格壳、读取态焦点链与窗口缩放钩子，打开、拖入与错误态的验收与限制未变，无行为变化；这次没有检查真机。 gardener 复核（a000dcd..cd36c04，2026-10-26）：PicseeApp.swift 的缓存实例改为共享并懒加载，CommandMenu 初始化增加设置参数；OPEN-02/03 的打开路径未变，验收与状态未变。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：OPEN-01/04/05/06 在哪含 CanvasWindowController.swift，本次只增加网格缩略图加载器注入与关窗时停止缩略图，打开、拖入与空态路径未变，状态与验收未变；这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：CanvasWindowController 改动限于网格选择与预览入口接线，OPEN 各行行为与验收未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：CanvasWindowController 只接线元数据排序状态，OPEN-01/02/04/05/06 的打开与默认排序路径未变，状态与验证未变。；P2-07（2bd7c37..c378d87）：OPEN-02/03 仅接入前台对账，OPEN-06「运行中目录消失首次即提示重连」与 FOLDER-07 刷新失败路径可能冲突，待 owner 核对（见 PROPOSED）。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26，P3-10 切片 2）：OPEN-01/02/04/05/06 的 CanvasWindowController 改动只增加搜索投影取消与目录打开时的网格搜索重置；错误态返回网格改经 GridWatchedSearchRefresh.restoreGrid，同样显示网格。OPEN-01 的底部搜索与排序按钮在 ViewerChromeOverlay 中仍由 isEnabled 为 false 禁用，空态未变；状态与验收未变。这次没有检查真机。 gardener 复核（ad73ea1..cacea91，2026-10-26，#123）：ViewerImageStatus 仅在筛选等待中显示读取态，OPEN-01 空态路径未变；OPEN-05 限制已写明过滤后与扫描中重试仅单元，怎么确认与状态未变。这次没有检查真机。 gardener 复核（6788e31..8f7f2fe，2026-10-27）：OPEN-03 所在的 ViewerSession 改动只新增预览结束后重放文件夹排序，单图打开的验收与状态未变；无提议。 gardener 复核（ad73ea1..bf58817，2026-10-27）：OPEN-06 因 P3-14 被映射，RecentFolderStore 与 FileAccess 未改，状态与验收未变。 |
| 查看与画布 | 2026-10-27 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..0bcbb90）：0bcbb90 只改开发计划状态措辞，补记 P0-03 另有 MacBook @2x 记录，与 VIEW-02/03 已链接的 P0 @2x/@1x 记录一致；无代码、无验证记录，VIEW 各行状态与验收未变。上次：P2-03（#89，d26e164..057462f）。d87bdf1..83c1457（P3-03/04）：ImageIOPipeline 增加缓存注入与 imageFresh，DecodeAdmission 增加可选复用；VIEW-06/07 的缓存命中方向与透明需 PR 行的「无用户可见变化」确认，VIEW-08 已记磁盘缓存路径；状态未变，无真机记录。gardener 复核（54ea1c1，范围 4ff189d..54ea1c1）：VIEW-06/07 已恢复为 main 文本，本范围未改；VIEW-08 限制改指 CACHE-02，「怎么确认」约 157 个可见字（两句），状态与验证未变，无真机升级。gardener 复核（fe9cffb，范围 4ff189d..fe9cffb）：VIEW-08 限制只改为引用 CACHE-02，「怎么确认」约 148 个可见字（两句），状态与验证未变，无真机升级。gardener 复核（#122，b321769..4c30eec，2026-10-25）：VIEW-09 限制恢复「仅见一次」与「#58 消耗重试后的延迟旧查找」，#122 迟到旧 pin、旧观察与取消仅单测；ImageIOPipeline 取消与修订检查不改解码，VIEW-06/07/08 判为不受影响。VIEW-09「怎么确认」约 178 个可见字，超出约 150 字指引，待 owner 压缩；状态与验证未变，无真机升级。 gardener 复核（0cbd129..3d2fba3）：VIEW-10 限制已更新为预览集首尾停止（单元）；VIEW-01/02/03/05 的适应、缩放、全屏路径未见改动，状态与验证未变；VIEW-09 未追溯 presentGridItem 路径。 gardener 复核（0cbd129..a3ec010）：VIEW-10 限制已含 P3-01 冻结预览集首尾停止；VIEW-01…05 的适应、1:1、缩放、平移、全屏代码在本范围无改动，状态与验证未变；VIEW-09 的切图代码未改。 gardener 复核（0cbd129..a5c8c4a）：VIEW-09 压缩后删去“本修复真机未验”，但“同代次重试与 #58 延迟查找仅单元”仍覆盖未验边界，未提议；VIEW-01…08 的画布代码本范围无改动，VIEW-10 的网格预览首尾停止已在限制中。 gardener 复核（0cbd129..0d55474）：VIEW-01/02/03/05 的适应、1:1、缩放、全屏代码未改（ViewerSession 新增仅 Esc、Space、Enter 路由）；VIEW-10 限制已含 P3-01 预览集首尾停止。VIEW-09 提议：网格预览经 presentGridItem 复用 open 路径，网格内快速翻图未验，限制待 owner 补一句（见 PROPOSED）。 gardener 复核（0cbd129..b39c6b8）：VIEW-09 限制增写“本修复与网格内快速翻图真机未验”，怎么确认与状态未变，无真机升级。 gardener 复核（4226e7c..e63bba7，2026-10-25）：VIEW-09 限制已写明网格内快速翻图仅单元，VIEW-10 限制已写明 P3-01 预览集首尾停止仅单元；VIEW-01…05 的适应、1:1、缩放、平移、全屏代码本范围未改，状态与验证未变。VIEW-09、VIEW-10 的怎么确认超过约 150 字，待 owner 压缩（PROPOSED）。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04）：VIEW-10 限制已补递归快照；VIEW-05 只因 View 菜单新增「包含子文件夹」项被路径触及，全屏行为未变。这次没有检查什么：真机与 @2x。 gardener 复核（1bebf9d..9442a18，2026-10-26）：VIEW-05 仅 CommandMenu 新增侧栏菜单项，全屏行为未变，状态与验收未变。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：VIEW-05/10 的 CommandMenu 与 CanvasWindowController 改动不改变全屏与切图路径，状态与验收未变；VIEW-05、VIEW-10 超约 150 字（PROPOSED）。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：VIEW-05/10 路径含 CanvasWindowController.swift 与 CommandMenu.swift，改动限于网格壳显隐、子视图顺序与新增菜单项，查看态的全屏与翻图路径未变，无行为变化；这次没有检查真机。 gardener 复核（a000dcd..cd36c04，2026-10-26）：CommandMenu.swift 仅新增 Picsee 菜单「设置…」项与其 validate 分支；VIEW-05/10 的验收与状态未变。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：VIEW-05 路径含 CanvasWindowController.swift，本次改动只限网格缩略图加载与关窗停止，全屏与翻图路径未变，状态与验收未变；这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：ViewerSession 仅新增 clearSelection 接口，VIEW 各行行为与验收未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：VIEW-05/10 的路径仅增加排序提示、菜单工具提示与接线，默认翻图顺序未变；元数据排序下的翻图仅单元（见 FOLDER-06），状态与验证未变。；P2-07：`ViewerSession` 仅在浏览态移走当前项时改到最近幸存项，VIEW 行无用户可见变化；浏览态筛选移项见 FOLDER-03 提议。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26）：VIEW-05 的全屏路径未变；VIEW-10 的 ←/→ 在网格搜索后进入大图时只在筛选结果内翻图，语义同 FOLDER-03，未写进限制，见 PROPOSED（GRID-07）；状态与验收未变。 gardener 复核（ad73ea1..cacea91，2026-10-26，#123 P2-03）：VIEW-10 计划含 P2-03，但本范围未改导航、首尾停止或画布代码，状态与验收未变；无 VIEW 行的在哪含本范围改动文件。这次没有检查真机。 gardener 复核（6788e31..8f7f2fe，2026-10-27）：VIEW-01/02/03/05/09 经 ViewerSession 的改动只涉及文件夹排序保存与重放，VIEW-10 经 FolderSnapshotNavigation 的改动只在设置文件夹条件时保存排序；验收与状态未变；无提议。 |
| C 沉浸界面 | 2026-10-27 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；CHROME-04/05 因 P3-11/P3-01 被映射；CHROME-05 验收于 6689c79 按 ADR-0010 改写（单图 Esc 回文件夹网格待 P3-01），状态与验证未变；未合入 P3-01 分支的探查运行不是验证记录。 gardener 复核（0cbd129..3d2fba3）：CHROME-05 限制已写明网格来源仅单元；CHROME-01…04 的工具显隐与固定逻辑未见改动，网格标题栏常驻记入 GRID-01。 gardener 复核（0cbd129..a3ec010）：CHROME-05 限制已写明网格来源与单图回网格仅单元；网格可见时红绿灯常驻（ChromeTitlebarPolicy.trafficLightsVisible）只作用于网格，CHROME-01 的工具显隐规则未变，记入 GRID-01。 gardener 复核（0cbd129..a5c8c4a）：CHROME-05 限制与代码一致（网格来源与单图回网格仅单元）；CHROME-01…04 未变。 gardener 复核（0cbd129..0d55474）：CHROME-01…04 的工具隐藏规则未变（ChromeTitlebarPolicy.trafficLightsVisible 在网格不可见时返回原值）；网格常驻红绿灯记入 GRID-01。CHROME-05 限制已写明网格来源与单图回网格仅单元。 gardener 复核（4226e7c..e63bba7，2026-10-25）：CHROME-05 限制已写明网格来源与单图回网格仅单元；CHROME-01…04 的工具显隐规则未变（网格常驻标题栏记入 GRID-01）。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04）：CHROME-01…04 路径仅触及 CanvasWindowController 的扫描开始、结束、完成钩子（只调 chromeOverlay.refresh）；ViewerChromeOverlay 与显隐规则未改，状态与验收未变。这次没有检查什么：真机与 @2x。 gardener 复核（1bebf9d..9442a18，2026-10-26）：chromeOverlay 层序调整，网格显示时工具本就隐藏，CHROME-01…05 的工具规则未变；CHROME-04 新增的偏好键未改 alwaysShowTools 行为。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：CHROME-01/02/03 的 CanvasWindowController 改动（网格壳只在网格态可见，查看态工具层级相对顺序不变）与 CHROME-04 的 DisplayPreferences、CommandMenu 改动（新增键与菜单项，不改工具常驻值）未改变工具行为，状态与验收未变；CHROME-01/02/03 超约 150 字（PROPOSED）。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：CHROME-01/02/03 路径含 CanvasWindowController.swift，工具层子视图顺序变化，查看态隐藏网格壳，显隐计时与焦点未变；CHROME-04 的 DisplayPreferences 新增侧栏键带默认值，常驻开关未变；这次没有检查真机。 gardener 复核（a000dcd..cd36c04，2026-10-26）：CommandMenu.swift 仅新增设置菜单项；CHROME-03/04 的工具显隐与固定逻辑未变，状态未变。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：CHROME-01…03 路径含 CanvasWindowController.swift，本次改动只限网格缩略图加载与关窗停止，工具显隐与固定逻辑未变，状态与验收未变；这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：从网格进入的大图 Esc 返回后恢复进入前的多选集合，CHROME-05 验收与限制（网格来源仅单元）未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：ViewerChromeOverlay 增加仅在按拍摄日期或像素面积排序未完成时可见的提示，CHROME-01…05 的工具显隐未改；提示与工具自动隐藏的组合真机未验（FOLDER-06 限制）。状态与验证未变。；P2-07：CHROME-01…05 仅经 `CanvasWindowController`/`ViewerSession` 接线，无用户可见变化。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26）：CHROME-01…04 的 CanvasWindowController 改动把 Esc 判定抽成 InspectorEscapePolicy，条件与原 guard 等价；工具显隐、唤回与常驻路径未变；状态与验收未变。 gardener 复核（6788e31..8f7f2fe，2026-10-27）：CHROME-01…05 经 ViewerSession 与 DisplayPreferences 的改动只涉及文件夹排序键，工具与显示行为未变；无提议。 |
| 外观与显示偏好 | 2026-10-27 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；PREF-03 因 P3-11 被映射，保持 Absent。 gardener 复核（0cbd129..3d2fba3）：PREF-01 未见路径改动；PREF-02 的动画路径未追溯，待 owner 确认。 gardener 复核（0cbd129..a3ec010）：PREF-02 的动画路径已追溯：本范围没有新增或改动动画调用，状态与验证未变；PREF-01/04 的代码未改。 gardener 复核（0cbd129..0d55474）：PREF-01 的 CommandMenu 改动只是新增网格项，偏好与外观代码未改；PREF-02 本范围新增代码无动画调用，状态与验证未变。 gardener 复核（4226e7c..e63bba7，2026-10-25）：PREF-01 只因 CommandMenu 新增网格项受影响，偏好与外观代码未改；PREF-02 无新增动画调用；状态与验证未变。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04）：PREF-01/02 路径仅触及 CommandMenu 与 CanvasWindowController 中既有代码，显示偏好与动效规则未改。这次没有检查什么：真机。 gardener 复核（1bebf9d..9442a18，2026-10-26）：DisplayPreferences 新增 gridSidebarWidth、gridSidebarVisible 两键，存储去掉 @Observable（无消费者），观察者通知未变；键名未写入账簿，提议见 GRID-06。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：PREF-01/02/04 的 DisplayPreferences 与 UserDefaultsDisplayPreferencesStore 改动只增加侧栏宽度与显隐两键并夹取宽度；移除 @Observable 后仍经 observer 通知窗口外观，外观与同步路径未变，状态与验收未变。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：DisplayPreferences 新增 gridSidebarWidth、gridSidebarVisible（带默认值与解码回退）；UserDefaults 与内存存储去掉 @Observable、改为手动通知，观察者机制不变，PREF-01/02/04 无行为变化；PREF-03 仍 Absent；这次没有检查真机。 gardener 复核（a000dcd..cd36c04，2026-10-26）：CommandMenu.swift 仅新增设置菜单项；PREF-01 的偏好与菜单路径未变，状态未变。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：PREF-02 路径含 CanvasWindowController.swift，本次改动与偏好读写无关，状态与验收未变。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：本范围无偏好或动画改动，PREF-02 未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：PREF-01/02 路径只接线菜单工具提示与提示视图，无偏好键、无动画改动，状态与验证未变。；P2-07：PREF-02 路径仅经 `CanvasWindowController` 接线，无用户可见变化。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26）：PREF-01/02 的 CommandMenu 只新增 View 菜单的搜索项与其校验分支，外观与动态效果菜单未变；状态与验收未变。 gardener 复核（6788e31..8f7f2fe，2026-10-27）：PREF-01 经 DisplayPreferences 新增排序键，外观字段未变；PREF-04 的窗口间同步应覆盖新排序键，限制未写，待 owner 确认（提议）。 |
| 文件夹浏览 | 2026-10-27 | doc-gardener | 2026-10-25 grilling（ADR-0010）：FOLDER-01 能力名改为“扫描后进入网格”，FOLDER-01/02/03 验收按用户原话分别单独改写；FOLDER-01 限制保留扫描中临时顺序、读取后状态（P2-09）与首图/读取/取消真机未验，并压缩到约 140 字。状态与验证未变。gardener 复核（22f4d98）：FOLDER-01 怎么确认已压缩到约 140 字，7411cb0 时的长度待决项已关闭；42fb3d7、e56b0d2、22f4d98 三次改写未削弱验收，限制与记录链接均保留。上次待 owner 项已关闭：22f4d98 把 FOLDER-01 限制链接改为「@1x 记录」并注明耗时未测，P2-02 段确无耗时数据。 gardener 复核（0cbd129..3d2fba3）：FOLDER-01 限制已写明网格入口仅单元；FOLDER-02/03 的取消恢复点与排序、过滤状态未追溯。 gardener 复核（0cbd129..a3ec010）：FOLDER-01 限制已写明网格入口与取消恢复仅单元。FOLDER-02/03 待 owner：取消读取现恢复上一文件夹的排序与过滤条件（FolderScanRestorePoint），限制未写。 已解决：FOLDER-02/03 限制现写明取消恢复为 P3-01 仅单元。gardener 复核（0cbd129..a5c8c4a）：FOLDER-01 未见改动。 gardener 复核（0cbd129..0d55474）：FOLDER-01/02/03 限制已写明网格入口与取消恢复排序、过滤仅单元（P3-01），验收未变。 gardener 复核（4226e7c..e63bba7，2026-10-25）：FOLDER-01/02/03 限制已写明网格入口与取消恢复排序、过滤仅单元（P3-01），验收未变。FOLDER-01 怎么确认约 170 字，待 owner 确认长度（PROPOSED）。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04 #102）：FOLDER-04/05 由 Absent 升为 Partial/单元，验收句未改，链接的 validation/P2.md 记录存在且含行 ID；FOLDER-01/03/04/05/VIEW-10 的「怎么确认」超过约 150 字或三句（提议 owner 压缩限制）；FOLDER-02 路径触及的递归结果排序未核（提议 owner 确认是否写入限制）。这次没有检查什么：真机、@2x，以及递归结果的排序代码路径。 gardener 复核（1bebf9d..14b3022，2026-10-26，P2-04 第四轮）：0968c1f 与 14b3022 的 FOLDER-01/04/05 限制与代码一致（网格中切换递归按读取重扫，取消回原网格，失败显示 Retry，Retry 保留当前图）；三行「怎么确认」逐字未改，状态与验证未变（Partial/单元），无真机升级。FOLDER-01/04/05 的「怎么确认」超过约 150 字（约 238/339/291 字），仓库内无例外记录，待 owner 决定压缩或记录例外（PROPOSED）。这次没有检查什么：签名 App 中网格递归切换、标题栏与 AX。 gardener 复核（1bebf9d..9442a18，2026-10-26）：读取态移入网格壳并显示文件夹名；FOLDER-01 限制已写明网格入口与读取态仅单元，状态与验收未变。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：FOLDER-01/02/03 的 CanvasWindowController 与 CommandMenu 改动（网格壳、读取态焦点链、菜单标题）不改变扫描、排序与扩展名过滤，状态与验收未变；FOLDER-01 177 字超约 150 字（PROPOSED）。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：FOLDER-01 提议：打开文件夹的读取态经 showGrid(reading: true) 置于网格壳主列，侧栏可见时与侧栏并列，限制中未写明（PROPOSED）；FOLDER-02/03/04 的菜单与路径未变；这次没有检查真机读取态布局。 gardener 复核（a000dcd..cd36c04，2026-10-26）：CommandMenu.swift 仅新增设置菜单项；FOLDER-02/03/04 的菜单路径与验收未变，状态未变。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：FOLDER-01/04 路径含 CanvasWindowController.swift，本次只增加缩略图加载器与关窗停止，递归扫描与读取态路径未变，状态与验收未变；这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：扫描完成后的网格显示改用选择模型，FOLDER-01/04 验收与限制未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：FOLDER-06 由 Absent 升为 Partial/单元，验收前缀逐字不变；FOLDER-02 的交叉引用与 ACCESS-05 的租约释放限制待 owner 确认（提议见各行）；FOLDER-01/03/04/05 的扫描与投影改动只在元数据排序下生效，默认路径未变。 gardener 复核（1e3885f..7c41625，2026-10-26，#108 CI 挂起修复）：FOLDER-06 限制补记同步头信息读取移离 cooperative executor（仅单元），验收前缀、状态与验证未变；FOLDER-03/04/05 共享 FolderScanCoordinator 中的元数据读取路径，默认无排序时不触及，判为无用户可见变化；这次没有检查真机。；P2-07：FOLDER-07 升为 Partial/单元已在 c378d87 完成，验收未改；FOLDER-03 限制缺浏览态筛选移项，见 PROPOSED。 gardener 复核（6486ef8..dc76643，2026-10-26，#134 排序未完成卡住修复）：dc76643 只在刷新改变快照时重启元数据读取；FOLDER-06/07 限制已写明监听刷新下的元数据行为仅单元，怎么确认、状态与验证未变；FOLDER-01…05 的默认路径未触及。这次没有检查真机。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26，P3-10 切片 2）：FOLDER-02 限制补入底栏排序入口复用菜单条件仅单元；FOLDER-07 的监听刷新在网格搜索中改由 GridWatchedSearchRefresh 重新筛选，行内限制未写此行为，见 PROPOSED；FOLDER-01/03/04 的默认路径未变（FOLDER-04 取消恢复网格改经 completeGridDisplay，无搜索词时结果同前）。这次没有检查真机。 gardener 复核（ad73ea1..cacea91，2026-10-26，#123 P2-03）：FOLDER-03 限制写入无匹配只在扫描完成后呈现、筛选等待中失败显示 Retry、首个可用批次选 Current，与 FolderScanCoordinator 与 FolderNoMatchesCompletionTests 一致，「怎么确认」未改，状态与验证未变；FOLDER-07 的 applyRefresh 对不在上一导航顺序中的当前项改为首张可见项，限制未写（提议 owner 补一句，仅单元）；FOLDER-01/02/04/05/06 判为不受影响。这次没有检查真机。 gardener 复核（6788e31..8f7f2fe，2026-10-27）：FOLDER-02/03/06 限制随 #124 改写（排序跨范围保留，过滤按文件夹清空），验收未变；FOLDER-02 限制里「取消读取恢复上一文件夹过滤」与过滤条款混写，另有过滤专属的符号链接句，待 owner 改写（提议）。 |
| Filmstrip | 2026-10-25 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；FILM-01/02 因 P2-06 被映射，保持 Absent。 |
| 网格、选择与菜单 | 2026-10-27 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；GRID 各行因 P3-01…15 被映射；P3-01 签名 App 探查明确不是验证记录、代码未合入，GRID-01/02 等保持 Absent；0bcbb90 提交标题提到 GRID-15：计划头不再称已合入工作包的账簿行均为 Partial，与 GRID-15（计划含 P2-01）保持 Absent 一致。2026-10-25 P3-15 推迟（a951e00）：GRID-15/16 计划仍写 P3-15，保持 Absent，无行为变化。 gardener 复核（0cbd129..3d2fba3）：GRID-01/02 由 Absent 升为 Partial/单元，验收句未改（仅补句号）；两行「怎么确认」约 235、256 个可见字，超过约 150 字，提议 owner 压缩限制。 gardener 复核（0cbd129..a3ec010）：GRID-01/02 限制已压缩，「怎么确认」验收句与 0cbd129 逐字相同（仅补句号），约 146/135 字符；状态 Absent→Partial/单元，验收未削弱。 gardener 复核（0cbd129..a5c8c4a）：GRID-01/02 在 0cbd129 之后只补句号，状态 Absent→Partial/单元，限制完整，无 BLOCK。 gardener 复核（0cbd129..0d55474）：GRID-01/02 状态 Absent→Partial/单元，验收句仅句末补「。」，限制完整；0d55474 恢复的限定与 GRID 行一致。新增 grid.cell、grid.photo、grid.collection 无障碍标识不是账簿要求的声明名。 gardener 复核（4226e7c..e63bba7，2026-10-25）：GRID-01/02 由 Absent 升为 Partial、验证为单元；怎么确认只在句末补「。」，限制写明仅单元及签名真机、@2x、VoiceOver、中英文未验。docs/validation 中尚无 P3-01 真机记录，未升至真机。GRID-01 怎么确认约 190 字，待 owner 压缩（PROPOSED）。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04）：GRID-01/02 路径仅触及 CanvasWindowController 的扫描钩子；递归结果作为同一快照进入网格，记入 FOLDER-04，GRID 行状态与验收未变。这次没有检查什么：真机、递归网格的实际内容。 gardener 复核（1bebf9d..14b3022，2026-10-26，P2-04 第四轮）：GRID-01 路径 FolderGridProjection.swift 的改动是网格保留完整快照直到新的完整快照到达（取消读取回到不变的网格）；快照已在 GRID-01 限制中写为仅单元，递归网格重扫的读取与 Retry 记入 FOLDER-01/04。GRID 行状态与验收未变。这次没有检查什么：真机网格递归切换。 gardener 复核（1bebf9d..9442a18，2026-10-26）：GRID-01/06/08 升为 Partial/单元，验收句未改（GRID-06、GRID-08 仅补句号）。提议：GRID-01 怎么确认约 237 字需压缩；GRID-06 在哪缺 CommandMenu.swift、菜单 ID 与偏好键名；GRID-02 补侧栏显隐后的网格仅单元限制。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：GRID-02/06/08 的限制与路径（含 GridShellView.swift、CommandMenu 菜单 ID、偏好键）与 head 代码和单元测试名一致，怎么确认未改；GRID-01 的「搜索、排序、信息与显示」归属有误（信息属 P3-13，显示属 P3-11），且 GRID-01 怎么确认 237 字、GRID-02 193 字超约 150 字，待 owner（PROPOSED）；GRID-01 在哪未列 GridShellView.swift，GRID-06 未点名 ⌃⌘S，待 owner（PROPOSED）。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：GRID-01/06/08 的限制、路径、菜单 ID（grid.sidebar.toggle.menu）与偏好键与 head 代码和单元测试名一致，验收句未改（GRID-06、GRID-08 仅句末补「。」）；GRID-02 在哪未列 GridViewerPresentation.swift，提议补入（PROPOSED）；GRID-02 限制中的「本轮」与 GRID-08 限制中的「本 slice」「后续工具加入后须复验」不是事实，提议改写（PROPOSED）；GRID-07、GRID-14 无搜索与子文件夹树，保持 Absent；这次没有检查真机。 gardener 复核（a000dcd..cd36c04，2026-10-26）：CommandMenu.swift 仅新增设置菜单项；GRID-06 的目录侧栏路径未变，状态未变。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：GRID-03 由 Absent 升为 Partial/单元，怎么确认的验收句未改（仅句末补「。」），限制写明可见区请求、取消、身份与修订校验、失败回放与优先级仅单元，S2 真机与 @2x 未验；GRID-01 限制改为缩略图装载仅单元；GRID-02 路径的大图期间暂停缩略图属内部行为，验收未变，判为不受影响；GRID-06/08 只受关窗停止影响，未变。这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，P3-09 多选，2026-10-26）：GRID-04/05 由 Absent 升为 Partial/单元，「怎么确认」句未改（末尾多出一个「。」，待 owner 还原）；GRID-02 限制改为多选单元覆盖，「App 接线无测试」属实（AppTests 无网格用例）；GRID-01/03/06 限制与本次改动相符，未改。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：GridBrowserView 增加默认隐藏、不拦截点击的排序提示；GRID-01/03/04/05/06/08 默认网格、选择与布局未变，状态与验证未变。；P2-07：GRID-01、GRID-04 的外部变化刷新（静默刷新、选择收缩）未写进限制，见 PROPOSED。 gardener 复核（58d8517..42b160d，2026-10-26，P3-10 测试辅助）：只改 PicseeMacUITests 的 PinnedDesign 测试辅助与其测试，无 App 代码、无用户可见变化；GRID-01/06/07/08/14 与 A11Y-01 状态与验收未变。这次没有检查真机。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26，P3-10 切片 2）：GRID-07 由 Absent 升为 Partial（单元），验收文字未改，仅补句号；GRID-01/08 限制同步底栏搜索与排序入口仅单元；GRID-07 限制未写搜索中的监听刷新与搜索后大图内翻图，见 PROPOSED；GRID-02/03/04/05/06 的默认路径未变。这次没有检查真机。 gardener 复核（6788e31..8f7f2fe，2026-10-27）：GRID-02 与 GRID-06 经 ViewerSession 与 DisplayPreferences 的改动与方向键和侧栏无关，验收未变；无提议。 gardener 复核（ad73ea1..bf58817，2026-10-27，P3-14 切片 1）：GRID-12、GRID-17 由 Absent 升为 Partial/单元，「怎么确认」验收文本未改，限制写明心形、侧栏与访问记录未接线；「重启后仍在」的依据是存储单元测试，App 尚未接入存储路径（已在限制中注明为仅存储）。 |
| 信息与元数据 | 2026-10-26 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；INFO-01/02 因 P3-13 被映射，保持 Absent。 gardener 复核（af1bff7..8552ec2，2026-10-26）：INFO-01/02 仅因提交正文提到 P3-13 被映射，本切片未实现，保持 Absent，无行为变化。 |
| 授权与文件访问 | 2026-10-26 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；ACCESS-04 因 P2-08 被映射，保持 Absent。d87bdf1..83c1457（P3-03/04）：AccessImageSource 在 withLease 内做缓存查找与写入，租约范围与释放日志语义未改，ACCESS-05 行未改、状态未变；ACCESS-04 仍 Absent。 gardener 复核（0cbd129..3d2fba3）：ACCESS-01 未见改动；ACCESS-03 的重连后恢复限制早于网格入口，待 owner 确认；ACCESS-05 关窗释放路径未追溯。 gardener 复核（0cbd129..a3ec010）：ACCESS-03 限制已写明重选进网格仅单元；ACCESS-05 的关窗释放日志路径本次未追溯，待 owner 确认。 gardener 复核（0cbd129..a5c8c4a）：ACCESS-05 提议：P3-01 新增的单图回网格租约（CanvasWindowController.swift returnToFolder，2399b11）与进网格窗口的关窗释放无真机记录，限制待补。ACCESS-03 限制与代码一致。 gardener 复核（0cbd129..0d55474）：ACCESS-05 的 P3-01 单图回网格短租约与无真机记录限制已写入（0d55474）；其「怎么确认」加限制后约 158 个可见字，超过约 150 字，提议压缩（见 PROPOSED）。ACCESS-01 的 → 提示与授权面板路径未改；ACCESS-03 限制已写明重选进网格仅单元。 gardener 复核（0cbd129..b39c6b8）：ACCESS-05 限制压缩后保留 @1x 关窗释放记录与两条链接，怎么确认验收句未变（约 152 字）；网格窗口关窗仍未真机验，已写入限制。 gardener 复核（4226e7c..e63bba7，2026-10-25）：ACCESS-03 限制已写明网格接线仅单元，ACCESS-05 限制已写明 P3-01 单图回网格短租约仅单元；ACCESS-05 怎么确认约 330 字，待 owner 压缩（PROPOSED）。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04）：ACCESS-05 限制已补 P2-04 递归取消与失败的租约释放（仅单元），验收句未改；ACCESS-01/03 路径仅触及 CanvasWindowController，未变。这次没有检查什么：递归路径的真机关窗日志。 gardener 复核（1bebf9d..14b3022，2026-10-26，P2-04 第四轮）：14b3022 在 CanvasWindowController 的网格递归重扫接线（showReadingState、folderScanDidStart）归入 FOLDER-01/04；ACCESS-03/05 的限制未改，ACCESS-05 仍写明递归取消与失败租约仅单元，本轮未追溯租约释放路径。这次没有检查什么：网格递归重扫时的租约释放日志。 gardener 复核（1bebf9d..9442a18，2026-10-26）：ACCESS-01/03/05 的 CanvasWindowController 改动只限网格壳，授权路径未变，状态与验收未变。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：ACCESS-01/03/05 的 CanvasWindowController 改动只限网格壳与读取态焦点链，授权、提示与释放路径未变，状态与验收未变；ACCESS-01、ACCESS-05 超约 150 字（PROPOSED）。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：ACCESS-01/03/05 路径含 CanvasWindowController.swift，改动限于网格壳与焦点链，授权、重连与失效路径未变，无行为变化；这次没有检查真机。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：AccessImageSource 仅为解码请求增加 priority 参数，租约与释放语义未改，ACCESS-05 状态与验收未变；ACCESS-01/03 路径含 CanvasWindowController.swift，授权与重连路径未变；这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：单图回网格的恢复接线改动，ACCESS-03 限制（重选进网格仅单元）未变；ACCESS-01/05 未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：元数据读取新增按需 withLease 租约，ACCESS-01/03 未改；ACCESS-05 的新租约释放待 owner 确认（提议见 ACCESS-05）。状态与验证未变。；P2-07：ACCESS-05 的共享监听持有根租约，关窗释放的证据早于此次改动，见 PROPOSED。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26）：ACCESS-01/03/05 的 CanvasWindowController 改动只限搜索状态重置与监听刷新分支，授权打开与重连路径未变；状态与验收未变。 |
| 缓存与资源 | 2026-10-26 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；CACHE-01 因 P3-06、CACHE-02…04 因 P3-03…07 被映射；P3-03/04 未合入，CACHE-02 保持 Absent，CACHE-01 保持 Partial/单元。d87bdf1..83c1457（P3-03/04）：CACHE-02 由 Absent 升为 Partial/单元，验收前缀未改，限制写明仅查看器首预览、未接网格、无真机记录；CACHE-01 限制已改为磁盘缓存见 CACHE-02。上文「CACHE-02 保持 Absent」不再成立，以本行为准。gardener 复核（54ea1c1，范围 4ff189d..54ea1c1）：CACHE-02 限制只声明重开命中及方向 3/6、透明 @1x 已验（P3 查看器路径），「怎么确认」约 127 个可见字，状态与验证未变；网格、手删重建仍未验。gardener 复核（fe9cffb，范围 4ff189d..fe9cffb）：P3 记录的 CACHE-02 行与限制一致，「怎么确认」约 130 个可见字（一句），状态与验证未变。提议（owner 决定）：限制中“重开命中”的依据是推断（无源解码、索引 last_access 更新、载荷未改写，App 无命中日志，见 P3 运行段），可在限制中写明“推断”；记录执行者为 opus-auditor，而账簿写作真机测试角色 claude-imple-1，本行未升级，故未触发自证检查，升级前须确认。gardener 复核（#122，b321769..4c30eec，2026-10-25）：CACHE-01 限制恢复「一次复核」，#122 迟到旧 pin、旧观察与取消票据仅单测；「怎么确认」约 161 个可见字，超出约 150 字指引，待 owner 压缩。限制中的 `docs/validation/P3.md` 数据链接不含 CACHE-01 ID（b321769 时即如此），owner 可改指 P1 记录或注明无数据；状态与验证未变，无真机升级。 gardener 复核（0cbd129..a3ec010）：本范围无 Infrastructure 缓存或内存上限改动，CACHE-01/02 未变；CanvasWindowController 的网格接线不涉及两者。 gardener 复核（a000dcd..cd36c04，2026-10-26）：CACHE-03 由 Absent 升为 Partial/单元，验收前缀未改，限制写明无签名真机、@1x/@2x 未验；CACHE-02 的写入失败隔次重试与符号链接目录拒绝未写入其限制，待 owner 确认（提议）；CACHE-01 仅共享缓存实例，未改。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：CACHE-02 在哪补入 CanvasWindowController.swift，限制改为查看器与网格缩略图接线（网格 ≤1024 px 由 GridThumbnailScheduler 计算）；网格接线仅单元，网格重开加速与手删重建仍未验，验收句未改，状态与验证未变。此前提议的写入失败隔次重试与符号链接目录拒绝，现已写入 CACHE-02 限制。这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：CanvasWindowController 改动不涉及缓存路径，CACHE-02 未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：CACHE-02/03 路径只经 CanvasWindowController 接线与菜单，缓存读写未改，状态与验证未变。；P2-07：CACHE 行路径仅经 `App/PicseeApp.swift`、`CanvasWindowController` 接线，无用户可见变化。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26）：CACHE-02/03 所在文件的改动只新增搜索与排序的接线，缩略图缓存与缓存菜单未变；状态与验收未变。 |
| 命令与键盘 | 2026-10-27 | doc-gardener | P2-03（#89，d26e164..057462f）：新增 FolderMenuAction 标识已映射 FOLDER-02/03、VIEW-10；未增改 CommandRouter 命令 ID 或快捷键。CMD-01/02 的既有路由与菜单/输入框优先规则保留，新目录菜单组合真机未验。 gardener 复核（0cbd129..3d2fba3）：CMD-01 新增的 command.preview.menu、command.enter.menu 与代码生成规则一致；CMD-02 的 Esc 与 Space 路由证据早于分支，待 owner 确认。 gardener 复核（0cbd129..a5c8c4a）：CMD-02 限制已注明 P3-01 的 Esc 顺序与 Space/Enter 未复验，该待定项已闭合；CMD-01 压缩删去“真机”一字，提议恢复。 gardener 复核（0cbd129..0d55474）：CMD-01 新增 command.enter.menu（Open Selected Image）及 preview、enter 路由，限制已写明仅单元；CMD-02 限制已写明 P3-01 的 Esc 顺序与 Space、Enter 未复验；0d55474 恢复的「真机」限定与 CMD-01 行一致。 gardener 复核（4226e7c..e63bba7，2026-10-25）：CMD-01 已写明 command.preview.menu、command.enter.menu 接网格仅单元（CommandID 的 preview、enter 已在本行覆盖）；CMD-02 限制已写明 P3-01 Esc 顺序与 Space、Enter 预览未复验；无新增声明名。 gardener 复核（faa0f41..916f88b，2026-10-26，P2-04）：新菜单标识 folder.recursive.menu 已由 FOLDER-04 描述，满足声明名门禁；CMD-01/02 的快捷键与路由未改。这次没有检查什么：FOLDER-04 菜单勾选的真机结果。 gardener 复核（1bebf9d..9442a18，2026-10-26）：CommandMenu 新增 ⌃⌘S 侧栏菜单项，CMD-01 限制已写明新网格快捷键未验；菜单标识的账簿位置提议见 GRID-06。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：CMD-01/02 的 CommandMenu 新增 grid.sidebar.toggle.menu（⌃⌘S，网格可见时可用）与 CanvasWindowController 改动不改变既有路由与菜单优先规则，状态与验收未变；⌃⌘S 由 CMD-01 的「新网格快捷键与焦点未验」覆盖，GRID-06 未点名（PROPOSED）；CMD-01 156 字超约 150 字（PROPOSED）。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：CommandMenu 新增 grid.sidebar.toggle.menu（⌃⌘S，网格可见时可用），声明名已由 GRID-06 描述；CMD-01 的「新网格快捷键与焦点未验」覆盖该快捷键；CMD-02 无变化；这次没有检查真机。 gardener 复核（a000dcd..cd36c04，2026-10-26）：CommandMenu 新增「设置…」（⌘,，菜单标识 settings.menu），CMD-01 验收不含此项；ChromeWindowCommands.addClose 未改，⌘W 仍为单一 File › Close。CMD-01 限制中「既有菜单…真机一致」是否覆盖新菜单项，待 owner 确认（提议）。CMD-02 路由未变。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：CMD-01 路径含 CanvasWindowController.swift，本次改动只限网格缩略图加载与关窗停止，快捷键与路由未变，状态与验收未变；这次没有检查真机。 gardener 复核（98eb6b1..0d40be7，2026-10-26）：Space/Enter 进入网格预览改为按多选集合冻结，CMD-01 限制「preview/enter 接网格仅单元」仍成立；CMD-02 未变。 gardener 复核（2bd7c37..6962caf，#108 P2-05）：CommandMenu 仅为 pixelDimensions 菜单项增加工具提示，未增命令 ID、快捷键或偏好键；CMD-01/02 路由未变，排序菜单真机未验归 FOLDER-06。状态与验证未变。；P2-07：`ViewerSession` 改动不改快捷键或命令 ID，CMD-01/02 无用户可见变化。 gardener 复核（ad73ea1..ea4a0c1，2026-10-26，P3-10 切片 2）：CMD-01 新增 search 命令目录项、⌘F 菜单项（菜单 ID grid.search.menu 登记在 GRID-07）与 .search 路由；isEnabled 对 search 仍为 false，查看态 ⌘F 不可用，与限制一致；CMD-02 限制改指 Inspector 占位字段；CMD-01/02 验收未变。 gardener 复核（6788e31..8f7f2fe，2026-10-27）：CMD-01/02 的键位与菜单路由未变，预览结束后的排序重放不属于其验收；8f7f2fe 的 Ledger 尾注 CMD-01 已核对为无用户可见变化；无提议。 |
| 窗口与桌面工具 | 2026-10-22 | doc-gardener | P7-09 去掉自动更新，WIN-07 不受影响 |
| 编辑与导出 | 2026-10-22 | doc-gardener | EDIT-03 验收按 ADR-007 补替换与源文件拒绝，状态未变；EDIT-05 依赖 P5-04 写权限；「不做」里覆盖原文件一行的来源已补 ADR-007，决定与状态未变 |
| 格式 | 2026-10-25 | doc-gardener | #58 最新 main 复核（430e2a2..9a230ce）：ImageIOPipeline 只新增观察冲突后的文件头复核，支持格式、方向与颜色解码不变；FMT-01 保留既有状态及 @1x 记录，@2x 未验。上次：P1-07（fa2703f..d97615d），解码器与格式集合未改。d87bdf1..83c1457（P3-03/04）：ImageIOPipeline 增加缓存注入与 imageFresh，解码器集合与支持格式未改；缓存命中路径的格式表现需 PR 行的「无用户可见变化」确认，状态未变。gardener 复核（#122，b321769..4c30eec，2026-10-25）：ImageIOPipeline 只增加取消检查与修订复核，解码器集合、支持格式与颜色解码未改，FMT-01 判为不受影响；状态与验证未变。 |
| 可访问性与本地化 | 2026-10-27 | doc-gardener | 计划 v0.0.1 剩余任务（docs/plan-v001-remaining，00a5c6d..50a495a）：只改开发计划 §13/§14 与 docs/test 复核报告，无代码、无验证记录；A11Y-01 因 P3-10 被映射，保持 Absent。 gardener 复核（0cbd129..a3ec010）：A11Y-02 限制「选图/网格待 P3」已过时，待 owner 改写（提议）；网格新增字符串的中英文未验已记入 GRID-01。 gardener 复核（0cbd129..a5c8c4a）：A11Y-02 的“选图/网格待 P3”已改为“网格键盘选图与 Esc 返回仅单元（P3-01）”，a3ec010 的提议已解决。 gardener 复核（0cbd129..0d55474）：A11Y-02 限制已写明网格键盘选图与 Esc 返回仅单元；A11Y-04 新增 5 个字符串键（含 Selected、Open Selected Image 等）均有 en 与 zh-Hans，网格中英文界面未验已记入 GRID-01，本行状态与验收未变。 gardener 复核（4226e7c..e63bba7，2026-10-25）：A11Y-02 限制已写明网格键盘选图与 Esc 返回仅单元；A11Y-04 本范围新增网格字符串，网格中英文界面未验已记入 GRID-01，状态与验收未变。 gardener 复核（1bebf9d..9442a18，2026-10-26）：A11Y-02 网格焦点环新增侧栏切换与分隔条，提议写入限制；A11Y-04 新增三个侧栏字符串，提议写明中文显示未验；A11Y-01 仍 Absent。 gardener 复核（1bebf9d..7e1c7cf，2026-10-26）：A11Y-02 的限制（网格侧栏开关与分隔条 Tab 焦点、读取态焦点链）与 A11Y-04 的限制（「隐藏/显示/调整侧栏宽度」条目）与 head 的 GridShellView、Localizable.xcstrings 及测试名一致，怎么确认未改；A11Y-02 201 字超约 150 字（PROPOSED）。A11Y-01 因 P3-10 被映射，保持 Absent。 gardener 复核（af1bff7..8552ec2，2026-10-26，P3-10 切片 1）：A11Y-02 与 A11Y-04 的限制与 head 的 GridShellView、Localizable.xcstrings 及测试一致，验收句未改；A11Y-01 仍 Absent；这次没有检查 VoiceOver 与中文真机。 gardener 复核（a000dcd..cd36c04，2026-10-26）：Localizable.xcstrings 新增设置窗口字符串及中文译文（设置、缩略图缓存、清理缓存、缓存失败提示等）；未上屏、未验截断，待 owner 写入 A11Y-04 限制（提议）。 gardener 复核（c5b8ff9..a2ca2c0，2026-10-26，P3-02 #118）：Localizable.xcstrings 新增「Thumbnail unavailable」「thumbnail unavailable」及对应中文「无法显示缩略图」，由网格失败占位与其 VoiceOver 标签使用；A11Y-04 限制未点名该文案的中英文上屏，PROPOSED，待 owner 写入限制。A11Y-02 路径含 CanvasWindowController.swift，焦点路径未变。这次没有检查真机。；P2-07：A11Y-02 路径无快捷键改动，无用户可见变化。 gardener 复核（58d8517..42b160d，2026-10-26，P3-10 测试辅助）：只改 PicseeMacUITests 的 PinnedDesign 测试辅助与其测试，无 App 代码、无用户可见变化；GRID-01/06/07/08/14 与 A11Y-01 状态与验收未变。这次没有检查真机。 gardener 复核（6788e31..fbe721e，2026-10-27）：A11Y-02 路径含 ViewerSession.swift，本范围只增加预览结束后的排序回放与排序保存，键盘焦点与选图路径未变，状态与验收未变。这次没有检查真机。 |
| 分发 | 2026-10-26 | doc-gardener | P1-10 真机记录（validation/p1-10-device-mini，3996845..08c5ecf，run 20261023-212346-P1-10-DIST-06）：DIST-06 只改「限制：」（@1x Dock 与访达列表/图标视图通过），仍 `Partial`/`无`，验收不变；⌘Tab、浅色 Dock、@2x 未验。DIST-01…05 不变。上次：App 图标 Lens（feat/app-icon-lens，cfef98f..75127a2） gardener 复核（faa0f41..916f88b，2026-10-26，P2-04）：project.yml 仅新增 PicseeAppTests 测试 target，App 图标与分发配置未变，DIST-06 不变。这次没有检查什么：测试 target 的构建与运行。 |
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

### 2026-10-24 P2-03 在最新 main 上复核（d26e164..057462f）

FOLDER-02/03 的状态与验证仅升至 Partial/单元，逐提交核对验收前缀未变；OPEN-05、VIEW-10、FOLDER-01 的限制已对应过滤、同输入 Retry 与首图呈现的代码边界。新增目录菜单标识均在对应行中，涉及路径及既有验证链接有效，未发现 Shipped/真机升级。OPEN-05 合并现有 UI 证据后约 202 个可见字符，提议 owner 只压缩限制，保留验收、P1/#92 链接、JPEG/加载中未验以及 P2-03 原生组合未验。

这次没有检查什么：未运行测试、构建或 App，未读取审计报告或 PR 评论；未创建真机、性能、菜单/Retry/焦点、中文签名像素或 @1x/@2x 验收证据，源码与测试阅读不构成运行通过。

### 2026-10-24 P2-03 OPEN-05 限制压缩复核

owner 仅压缩 OPEN-05 的限制文本，全文约 165 个可见字符、两句；验收前缀、Partial/单元状态和代码路径未变。P3-01 网格/Esc、@1x 三类错误及重试的截断 PNG 证据、#92 构图/窄窗链接、截断 JPEG 与加载中未验，以及过滤后下一张、扫描中/后同图重试保留条件/权限仅单元和原生组合未验均保留；前轮长度提议已解决。

这次没有检查什么：未运行测试、构建或 App，未读取审计报告或 PR 评论；本次仅复核限制压缩与生成视图，不新增行为或真机验收证据。

### 2026-10-24 P3-03 磁盘缩略图缓存审查（00a5c6d..4e2685e）

本地 main 落后，本轮使用 origin/main 的 merge-base 00a5c6d。CACHE-02 的 Partial/单元升级未改原验收；没有 Shipped/真机升级，也未新增命令、菜单、偏好、entitlement 或 UTType 声明。原有路径与涉及的 P0/P1 记录有效；owner 须修正 CACHE-01 的无磁盘缓存声明，并压缩 CACHE-02 与 VIEW-08 的限制文本，验收及未验边界不得删减。ACCESS-04 仍 Absent，不能以租约拒绝单测代替运行中撤权验收。

这次没有检查什么：未运行测试、App 构建或真机，未读取审计报告或 PR 评论；源码与测试阅读不构成执行通过证据，未验网格接线、手删缓存重建、签名 sandbox 撤权、压力/S2/两窗口、性能及 @1x/@2x。HTML 同步检查不代表能力验收。

### 2026-10-24 P3-03 限制修订复核

复核 00a5c6d..4e2685e 及 owner 工作区修订：VIEW-08、CACHE-01、CACHE-02 的验收前缀逐字节不变，三行分别约 145、151、169 个可见字符，均不超过三句。CACHE-01 不再声称无磁盘缓存；CACHE-02 保留有限适用范围、仅单元和网格/手删重建/P3-04/05/08/签名真机未验，详细边界仍见 ADR-009。前轮三项提议均已解决；本次不升级状态或验证等级。

这次没有检查什么：未运行测试、构建或 App，未读取审计报告或 PR 评论；仅复核账簿工作区修订和 HTML 同步，不新增行为、性能或真机证据。

## 参考做法

- Anthropic，[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)：一开始就写出完整功能列表、全部标为未通过；每项带测试步骤；agent 只能改“是否通过”，不能删改测试；必须端到端验证后才能标为通过。对应本账簿的「先写好的验收」和「防止验收被悄悄放宽」。
- OpenAI，[Harness engineering](https://openai.com/index/harness-engineering/)：仓库里的文档是唯一可信的来源；AGENTS.md 只做目录，指向更深的文档；有一份按产品区域和架构层打分、跟踪缺口的质量文档，以及定期扫描过时文档的 doc-gardening agent。对应「区域审查」，以及 AGENTS.md 只链接本账簿、不复制内容。
- OpenAI Cookbook，[Using PLANS.md](https://developers.openai.com/cookbook/articles/codex_exec_plans)：计划是活文档，写给对项目毫无了解的读者。对应「怎么确认」必须是任何人都能照着做的操作。
- Google SRE，[Reliable Product Launches](https://sre.google/sre-book/reliable-product-launches/) 与 [Launch Coordination Checklist](https://sre.google/sre-book/launch-checklist/)：用户可见的变化都算发布；清单里每一项都要能说明为什么需要，每条操作都要具体可行；清单定期复审。对应「维护」和「发布门槛怎么读」。
- Meta，[Holistic Configuration Management at Facebook](https://blog.acolyer.org/2015/10/16/holistic-configuration-management-at-facebook/)（SOSP 2015）：新代码先以关闭状态上线，用 Gatekeeper 逐步放开；配置当作代码，由校验器自动检查不变量。对应「功能开关后面的能力」和门禁的机器检查。
- NASA 系统工程的需求验证矩阵（[NASA NTRS](https://ntrs.nasa.gov/api/citations/20160003166/downloads/20160003166.pdf)）：每条需求标明验证方法（测试、分析、检查、演示）。对应「验证」列。SpaceX 的“每条需求都要带上提出它的人的名字”（Isaacson《Elon Musk》）对应「计划」列：每行都能追溯到工作包和背后的用户决定。没有找到 SpaceX 公开的需求矩阵原文。
- mdpro 的 `docs/feature-ledger.md`：五值状态、`Partial` 必须写限制、路径从仓库根写、同一次提交更新行，都沿用；单元格长成修复史的问题，用 150 字上限和 validation 链接避免。
