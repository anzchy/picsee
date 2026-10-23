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
- `真机` 的记录按 `.claude/skills/macos-device-test/features/` 里该行的运行步骤做；还没有步骤的行，先写步骤再验证。

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

## 门禁（计划中，尚未实现）

`npm run ledger:check` 计划在 P0-01 建好工程后实现，作为 CI 和合入前检查的一项。它会检查：

1. 状态、验证两格都在枚举里；`Partial` 有 `限制：`；`Shipped` 的验证是 `真机` 且链接了 `docs/validation/`；
2. ID 不重复；计划一格的工作包 ID 在开发计划里存在；
3. 每个路径都能解析到文件；没有行号、计数和构建产物路径；`Absent` 的位置是 `—`；
4. App 声明的每个名字都出现在某一行：CommandRouter 的命令 ID、菜单项 identifier、`DisplayPreferences` 的键、entitlements、`Info.plist` 声明的 UTType；
5. 同一次提交里，某行状态升级的同时改写了「怎么确认」中的验收本身，报出来交给审查；只追加或修改「限制：」文本不报。

它**不能**判断一句话是不是真的：路径存在不代表那条行为还在。这需要真机复验和区域审查来补。

在脚本实现之前，合入审查时按上面五条人工核对。

`docs/feature-ledger.html` 是本文件的渲染视图，可按状态、阶段筛选和搜索，**由本文件生成，不要手改**。生成命令 `npm run ledger:build` 与 `ledger:check` 一起在 P0-01 后实现；在那之前 HTML 是某一时刻的快照，以底栏的生成时间为准，内容与本文件不一致时以本文件为准。

## 发布门槛怎么读

不单独维护一份发布清单，直接按「计划」一列筛选：

- **MVP（v0.0.1）**：计划为 P0–P3 的行，全部是 `Shipped`，或 `Partial` 且限制已被用户接受（引用原话）；
- **首发 v1**：计划为 P0–P6 的行，同样要求；格式类的行未达标时，从对外支持声明里删掉，而不是保留一个 `Partial`。

---

## Part 1 — picsee 现在有什么

### 打开与输入

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| OPEN-01 | 首次打开空态 | Absent | 无 | P1-02、P1-07 | — | 冷启动、没有打开过文件夹：显示 21 页空态，有“选择文件夹”按钮和拖入提示；底部搜索、排序、信息、显示按钮为禁用。⌘O 可选单张图片或文件夹 |
| OPEN-02 | 打开面板 | Partial | 无 | P0-09、P1-02 | `App/PicseeApp.swift`、`App/Commands/CommandMenu.swift` | ⌘O 选一张图或一个目录，画布显示该图；在面板里取消，当前状态不变。限制：无打开按钮；File › Open…、⌘O（图片与目录）与取消已 @1x 真机通过。 |
| OPEN-03 | 从 Finder 打开 | Stub | 无 | P1-02 | `App/Info.plist`、`App/PicseeApp.swift` | 在 Finder 对一张 JPEG 用“打开方式 → picsee”，App 启动并显示该图。限制：已声明 `public.image` 文档类型，真机运行中的 `open -a` 可用（见 [P0-03 真机记录](validation/P0.md#p0-03画布真机验收7view-02--view-03)）；Finder“打开方式”与双击未验；多文件仅显示首个文件。 |
| OPEN-04 | 拖入打开 | Absent | 无 | P1-02 | — | 从 Finder 拖一张图进窗口，显示该图；拖入不支持的文件给出明确提示，当前图不变 |
| OPEN-05 | 无法读取的图片 | Absent | 无 | P1-07、P2-03 | — | 打开截断的 JPEG：显示 25 页错误态，有“重试”和“下一张”；底部工具仍可用，可经网格按钮或 Esc 返回；不会显示上一张图 |
| OPEN-06 | 最近打开 | Partial | 单元 | P2-09、P3-14 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/RecentFolderStore.swift`、`App/Access/AccessMenus.swift` | 打开一个目录后退出重开，最近列表里有它；授权失效时显示重新授权入口；不保存图片副本。限制：重启后 Open Recent 浏览 @1x 真机通过；仅文件夹、最多 10 项；授权失效的重连入口未验；损坏库降级仅单元验证。 |
| OPEN-07 | 从剪贴板打开 | Absent | 无 | P4-02 | — | 截图到剪贴板后选“从剪贴板打开”，新窗口显示该图 |

### 查看与画布

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| VIEW-01 | 适应窗口 | Partial | 单元 | P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasPlacement.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 分别打开横图和竖图，都完整居中显示；拖动改窗口大小，图随之适应。限制：不超过 1× 适应、1× 时对齐 backing 网格；三入口与改窗口后重新适应 @1x 真机通过（[记录](validation/P1.md#运行-20261023-114600-view-01-04-05-minip1-0337mac-mini-1x)）；显式重开回到 fit；@2x 未验。 |
| VIEW-02 | 实际像素 1:1 | Partial | 单元 | P0-03、P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 按 1，在 2× 屏上一个图像像素对应一个物理像素；窗口拖到 1× 外接屏后仍是 1:1（27 页）。限制：P0-03 的 `1` 键在 [@2x](validation/P0.md#p0-03画布真机验收7view-02--view-03)、[@1x](validation/P0.md#p0-03画布真机验收-1x7view-02--view-03mac-mini) 已验；actualPixels 的路由 1/菜单/按钮真机未验；跨屏拖窗、中文和 VoiceOver 未验；多文件仅显示首个。 |
| VIEW-03 | 以光标为锚点缩放 | Partial | 单元 | P0-03、P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 触控板捏合或按 +/−，光标下的那个像素始终停在光标下。限制：zoomIn/zoomOut：P0-03 的 +/− 在 [@2x](validation/P0.md#p0-03画布真机验收7view-02--view-03)、[@1x](validation/P0.md#p0-03画布真机验收-1x7view-02--view-03mac-mini) 已验；捏合、完整 VoiceOver 未验；现按键路由/菜单/按钮真机未验；按钮或指针在面板/画布外时以中心缩放，锚点选择已单测。 |
| VIEW-04 | 平移与边界 | Partial | 单元 | P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 放大后拖动，图像不会被拖出可见范围；回到适应窗口后位置复原（27 页）；限制：四向边界与 0 复原 @1x 真机通过（合成拖动，[记录](validation/P1.md#运行-20261023-114600-view-01-04-05-minip1-0337mac-mini-1x)）；真实鼠标/触控板拖动与 @2x 未验。 |
| VIEW-05 | 全屏 | Partial | 单元 | P1-03 | `Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasTransform.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift` | ⌃⌘F 进入和退出全屏，当前图和缩放状态保持；限制：⌃⌘F 进出、适应重算 @1x 真机通过（[记录](validation/P1.md#运行-20261023-114600-view-01-04-05-minip1-0337mac-mini-1x)）；实际像素/自定义缩放下全屏、菜单与绿色按钮入口、@2x 未验。 |
| VIEW-06 | 按 EXIF 方向显示 | Partial | 单元 | P0-05、P1-03 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageIOPipeline.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 打开 S1 素材里八种 Orientation 的样本，全部正向显示；限制：@1x 真机方向 1–8 通过（[P0-05/06 记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)）；@2x 未验 |
| VIEW-07 | 透明图 | Partial | 单元 | P0-05 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/ImageIOPipeline.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 打开透明 PNG，透明区域按背景设置显示，不是黑色；限制：@1x 真机不发黑（[记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)）；尚无背景设置；@2x 未验 |
| VIEW-08 | 大图不卡界面 | Partial | 单元 | P0-05、P1-04 | `Packages/PicseeKit/Sources/PicseeInfrastructure/Images/DecodeAdmission.swift`、`Packages/PicseeKit/Sources/PicseeCore/Ports/ImagePipeline.swift`、`Packages/PicseeKit/Sources/PicseeCore/Canvas/CanvasDecodePolicy.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/FirstPreviewTracing.swift`、`Packages/PicseeKit/Sources/PicseeMacUI/Canvas/CanvasView.swift` | 打开 48MP 图：加载期间窗口能拖、菜单能开；先出预览再变清晰；限制：@1x 真机先预览再清晰（日志）、加载中经辅助功能移动窗口可响应（[记录](validation/P0.md#p0-0506解码真机验收9view-06--view-07--view-08--fmt-01mac-mini)）；鼠标拖动与菜单未验；48MP 以 45.4MP 代替；@2x 未验；该记录早于 P1-03 的重请求细节改动（同尺寸重装、缩放与全屏时），新路径真机未验；渐进档位（含预览覆盖视口或源图更小时仍请求首个非预览档，小于请求尺寸的细节返回不重复请求）、位深（含 16 位灰度）成本与资源上限仅单元证明；迁移后的独立真机验收未重跑。 |
| VIEW-09 | 快速切图不串图 | Partial | 单元 | P1-05 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageLoader.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerImageHost.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift` | 快速打开 A→B→C，让 A 最后才解码完：画布、标题、Inspector 都只显示 C；限制：“A 最后完成”仅单元证明（loadGenerationsCThenBThenALastBalancesLeases）；真机未验（无延迟钩子）；标题与 Inspector 仅显示文件名；同代次修订重试一次及关闭／失败清理已单测；修订重试清空旧像素后回 opening。 |
| VIEW-10 | 上一张 / 下一张 | Partial | 单元 | P2-03 | `Packages/PicseeKit/Sources/PicseeApplication/Access/FolderNavigation.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/ViewerSessionNavigationHost.swift`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift` | ←/→ 按目录顺序翻图；到首尾时按设置停止或循环。限制：按键/菜单/按钮 Finder 顺序、首尾停止 @1x 真机通过（[记录](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)）；无循环设置、筛选或排序（P2-03）。 |

### C 沉浸界面

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CHROME-01 | 工具自动隐藏 | Absent | 无 | P1-08 | — | 不动鼠标约 2.5 秒，底部三组工具和窗口红绿灯一起消失；隐藏后 Tab 聚焦不到、VoiceOver 读不到它们（13 页） |
| CHROME-02 | 唤回工具 | Absent | 无 | P1-08 | — | 鼠标移到底边或按 Tab，工具出现；移到顶部，红绿灯出现；按 Tab 时先唤回、再聚焦第一个控件（14 页） |
| CHROME-03 | 操作中不隐藏 | Absent | 无 | P1-08 | — | 打开菜单、拖动控件、Inspector 或 Filmstrip 展开时工具不消失；结束后重新计时 |
| CHROME-04 | 工具常驻 | Absent | 无 | P1-08、P3-11 | — | 开启“始终显示工具”，工具不再隐藏；退出重开后设置仍在 |
| CHROME-05 | Esc 返回来源 | Absent | 无 | P1-08、P3-01 | — | 从网格进入的大图按 Esc 回到网格；单独打开的图按 Esc 不会出现一个不存在的网格 |
| CHROME-06 | 固定窗口与全屏光标 | Absent | 无 | P4-03 | — | 全屏不动鼠标，光标随工具一起隐藏；固定窗口模式下窗口大小不随图片改变 |

### 外观与显示偏好

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| PREF-01 | 跟随系统 / 浅色 / 深色 | Absent | 无 | P1-09 | — | 默认跟随系统，系统外观切换时窗口即时变化；手动选深色后不再跟随（11/12 页） |
| PREF-02 | 减少动态效果 | Absent | 无 | P1-09 | — | 打开系统“减少动态效果”，工具显隐和面板切换没有动画 |
| PREF-03 | 显示设置 | Absent | 无 | P3-11 | — | 15 页：点底部右侧“显示”按钮弹出面板，调缩略图大小、显示文件名、填充裁剪 / 完整显示、外观、始终显示大图工具，立即生效，退出重开仍保留 |
| PREF-04 | 偏好在窗口间同步 | Absent | 无 | P1-09、P4-01 | — | 开两个窗口，在一个里改主题、Filmstrip 显隐或工具常驻，另一个窗口即时同步（ADR-002） |

### 文件夹浏览

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| FOLDER-01 | 边扫描边浏览 | Absent | 无 | P2-02 | — | 打开 S2（5000 项）：首批出现前显示 24 页读取状态，可取消；首批出现后即可翻图，扫描在后台继续（时间见 `docs/validation/P2.md`） |
| FOLDER-02 | 排序 | Absent | 无 | P2-03 | — | 按名称自然排序（img2 排在 img10 前）、修改日期、类型、大小，升降序都能切换 |
| FOLDER-03 | 扩展名过滤 | Absent | 无 | P2-03 | — | 只勾选 PNG，列表与翻图都只剩 PNG；取消过滤后恢复，当前图合理保留 |
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
| ACCESS-02 | 目录授权跨重启保留 | Partial | 单元 | P0-04、P2-01 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/`、`App/Resources/Picsee.entitlements`、`docs/adr/0008-folder-access-read-only-app-scoped-bookmarks.md` | 授权一个目录，退出重开后直接可浏览，不再弹授权。限制：重启与跨签名重建后均直接浏览（@1x 真机，[记录](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)）；损坏库与移动根仅单元验证；新增 `com.apple.security.files.bookmarks.app-scope`，保持只读。 |
| ACCESS-03 | 失效授权的修复 | Absent | 无 | P2-01 | — | 授权目录被移动后打开最近项，提示重新连接；重新选择后恢复浏览 |
| ACCESS-04 | 权限被撤销 | Absent | 无 | P2-08 | — | 浏览中撤销目录访问，显示 26 页提示并可重新授权；不会从缓存里继续显示原图 |
| ACCESS-05 | 访问范围用完即释放 | Partial | 单元 | P0-04 | `Packages/PicseeKit/Sources/PicseeInfrastructure/FileAccess/FileAccess.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Access/AccessImageSource.swift`、`App/CanvasWindowController.swift` | 打开再关闭授权目录的窗口，诊断日志显示访问范围已释放（方法见 `docs/validation/P0.md`）。限制：关闭窗口后 `remaining=0 outcome=released` @1x 真机通过（[记录](validation/P0.md#p0-04--p0-09授权与-session-真机验收811access-01--access-02--access-05--open-02--open-06--view-10--cmd-02--a11y-02mac-mini)）；日志不区分临时与租约会话。 |

### 缓存与资源

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CACHE-01 | 内存占用有上限 | Absent | 无 | P1-06、P3-06 | — | 连续浏览 S2 三轮，内存不持续增长；两个窗口共用同一个上限（数据见 `docs/validation/P3.md`） |
| CACHE-02 | 缩略图磁盘缓存 | Absent | 无 | P3-03、P3-04 | — | 第二次打开同一目录，网格明显更快出图；手动删掉缓存目录后自动重建，原图不受影响 |
| CACHE-03 | 清理缓存 | Absent | 无 | P3-05、P3-07 | — | 设置里显示缓存占用，点清理后占用归零，正在进行的旧任务不会把缓存重新写回 |
| CACHE-04 | 本地诊断面板 | Absent | 无 | P3-07 | — | 打开诊断面板，看到本地的解码数、队列长度、缓存命中；不上传任何数据 |

### 命令与键盘

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| CMD-01 | 基础快捷键 | Partial | 单元 | P0-09 | `Packages/PicseeKit/Sources/PicseeCore/Commands/`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/CommandRouter.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/Commands/CommandMenu.swift`、`App/CanvasWindowController.swift`、`App/UI/InspectorPlaceholder.swift` | Space、←/→、Esc、Enter、0/1、+/−、⌘F、⌘O、⌘I 在菜单、按钮和键盘上触发的是同一个动作；未实现的不在菜单里显示快捷键。限制：preview/enter/search 未实现；inspector、previous/next 三入口 @1x 真机一致；escape 菜单项 #29 已修。 |
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
| A11Y-02 | 纯键盘操作 | Partial | 单元 | P0-09、P6-04 | `Packages/PicseeKit/Sources/PicseeApplication/Viewer/InspectorFocus.swift`、`Packages/PicseeKit/Sources/PicseeApplication/Viewer/ViewerSession.swift`、`App/CanvasWindowController.swift`、`App/Commands/CommandMenu.swift`、`App/UI/InspectorPlaceholder.swift` | 不碰鼠标完成打开目录、选图、看大图、返回、打开 Inspector；焦点始终可见（28 页）。限制：选图/网格待 P3；⌘O 选目录、占位面板焦点与 Focus Canvas（#29 已修）@1x 真机通过；上一张/下一张按钮的 Tab 顺序未验。 |
| A11Y-03 | 对比度与焦点不被遮挡 | Absent | 无 | P6-04 | — | 浅色和深色下文字与控件对比度符合 `design/DESIGN.md` 的目标；获得焦点的控件不被其他元素挡住 |
| A11Y-04 | 中英文界面 | Absent | 无 | P1-07、P6-04 | — | 系统语言切到中文或英文，界面文字跟随变化，没有截断和未翻译的键名 |

### 分发

| ID | 能力 | 状态 | 验证 | 计划 | 在哪 | 怎么确认 |
|---|---|---|---|---|---|---|
| DIST-01 | 签名与公证 | Absent | 无 | P6-06 | — | 在另一台 Mac 上下载安装包后直接打开，Gatekeeper 不拦截；`spctl --assess` 通过 |
| DIST-02 | 全新环境可用 | Absent | 无 | P6-05 | — | 新建一个 macOS 用户首次打开，没有旧授权和缓存也能正常使用；损坏的缓存数据库能自动恢复 |
| DIST-03 | 安装包内容干净 | Absent | 无 | P6-07 | — | 检查 `.app` 内容，没有 REA、研究素材、私人照片或开发路径 |
| DIST-04 | 升级保留数据 | Absent | 无 | P6-08 | — | 用新版本覆盖旧版本，设置、收藏和目录授权都还在 |
| DIST-05 | 自动更新 | Absent | 无 | P6-08 | — | 有新版本时 App 提示更新，更新后签名校验通过 |

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
| 打开与输入 | 2026-10-23 | doc-gardener | P1 记录与真机步骤措辞（chore/followups-4，38a1846..11ee2ef）：P1.md 只加 P1-07/P1-09 归入依据，OPEN-01…05 仍无结果；状态不变。上次：P1-03 画布（#37，p1/p1-03-canvas，88fbb3d..d0727b5） |
| 查看与画布 | 2026-10-23 | doc-gardener | P1-03 真机记录（docs/p1-03-device-mini，1a08ba5..8644e0b）：P1.md 运行 `20261023-114600-VIEW-01-04-05-mini`（Validated-by picsee-delegator，单独提交）给 VIEW-01/04/05 @1x pass；同范围只改三行「限制：」，状态 `Partial`、验证 `单元` 与验收不变，显示行缺 @2x 不能升 `真机`；VIEW-02/03/06 只引用 P0 记录。上次：P1 记录与真机步骤措辞（chore/followups-4，38a1846..11ee2ef） |
| C 沉浸界面 | 2026-10-23 | doc-gardener | P1 记录与真机步骤措辞（chore/followups-4，38a1846..11ee2ef）：P1.md 注明 CHROME-04 持久化部分按开发计划 P1-09 文本归入（计划列 P1-08、P3-11），无结果；保持 `Absent`。上次：P1 素材与记录骨架（chore/followups-3，6f36f45..45fa1f8） |
| 外观与显示偏好 | 2026-10-23 | doc-gardener | P1 记录与真机步骤措辞（chore/followups-4，38a1846..11ee2ef）：P1.md 只加 PREF-01/02/04 的 P1-09 归入依据，无结果；保持 `Absent`。上次：P1 素材与记录骨架（chore/followups-3，6f36f45..45fa1f8） |
| 文件夹浏览 | 2026-10-21 | 建账 | 同上 |
| Filmstrip | 2026-10-23 | doc-gardener | P0-09 Session（#11/#29，dcfe3f8..bef71d5）：`filmstripExpanded` 键只作为 chrome 锁输入，无 Filmstrip UI；FILM-01 保持 `Absent`；PR 描述裁定键名待 P1-09（PREF-04）命名。上次：建账 |
| 网格、选择与菜单 | 2026-10-23 | doc-gardener | P0-09 Session（#11/#29，dcfe3f8..bef71d5）：BrowserSelection、Preview Set、瞬时搜索词与不可变右键目标只在 Application 与单元测试中，App 无网格入口，preview/enter/previous/next/search 仍未实现；GRID-02/04/05/07/09 保持 `Absent`。上次：建账 |
| 信息与元数据 | 2026-10-22 | doc-gardener | P0-09（#10，749697a..7054a5d）⌘I 只切换 Inspector 占位面板，无任何文件信息；INFO-01 保持 `Absent` |
| 授权与文件访问 | 2026-10-23 | doc-gardener | P1-03 画布（#37，p1/p1-03-canvas，88fbb3d..d0727b5）：`App/CanvasWindowController.swift` 只改画布构造、打开代次闭包、全屏行为与视口同步，授权提示、租约与释放未改；ACCESS-01/05 不受影响。上次：P1-01 身份（#36，p1/p1-01-identity，8beb967..a8fe43b） |
| 缓存与资源 | 2026-10-23 | doc-gardener | P1 记录与真机步骤措辞（chore/followups-4，38a1846..11ee2ef）：P1.md 的 CACHE-01 一节未改，仍无结果；保持 `Absent`。上次：P1 素材与记录骨架（chore/followups-3，6f36f45..45fa1f8） |
| 命令与键盘 | 2026-10-23 | doc-gardener | P1 记录与真机步骤措辞（chore/followups-4，38a1846..11ee2ef）：P1.md 注明 CMD-01 按开发计划 P1-07 文本归入（计划列 P0-09）；keyboard-commands.md 补面板可见时 Esc 回画布一步、参考运行改称 delegator 运行；无新证据，CMD-01/02 不变。上次：P1-03 画布（#37，p1/p1-03-canvas，88fbb3d..d0727b5） |
| 窗口与桌面工具 | 2026-10-22 | doc-gardener | P7-09 去掉自动更新，WIN-07 不受影响 |
| 编辑与导出 | 2026-10-22 | doc-gardener | EDIT-03 验收按 ADR-007 补替换与源文件拒绝，状态未变；EDIT-05 依赖 P5-04 写权限；「不做」里覆盖原文件一行的来源已补 ADR-007，决定与状态未变 |
| 格式 | 2026-10-23 | doc-gardener | P1-03 画布（#37，p1/p1-03-canvas，88fbb3d..d0727b5）：`App/CanvasWindowController.swift` 改动不涉及解码与格式；FMT-01 不受影响。上次：P1-01 身份（#36，p1/p1-01-identity，8beb967..a8fe43b） |
| 可访问性与本地化 | 2026-10-23 | doc-gardener | P1 记录与真机步骤措辞（chore/followups-4，38a1846..11ee2ef）：P1.md 注明 A11Y-02 按开发计划 P1-07 文本归入（计划列 P0-09、P6-04），A11Y-04 仍无结果；状态不变。上次：P1-03 画布（#37，p1/p1-03-canvas，88fbb3d..d0727b5） |
| 分发 | 2026-10-22 | doc-gardener | DIST-05 计划由 P7-09 移到 P6-08（ADR-006）；DIST-04 验收不变 |
| 增强 | 2026-10-21 | 建账 | 同上 |

### 2026-10-21 建账

依据开发计划 v0.2 的 P0–P7 工作包、1.0 节功能对应表和 1.3 节 20 页 mockup 映射，逐项建行。

这次没有检查什么：没有对照 Picview 实际运行逐项核对（Picview 功能见 `docs/PICVIEW_FEATURES.md`，只是静态资源证据）；没有对照 FastStone 调研报告补行；没有用户可见能力的工作包不单独建行：P0-01、P0-02、P0-06、P0-07（工程与技术验证）、P0-08（原生设计映射，体现在各 UI 行）、P1-01（身份与错误模型）、P3-08（规模验证，结果进 `docs/validation/P3.md`）。

## 参考做法

- Anthropic，[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)：一开始就写出完整功能列表、全部标为未通过；每项带测试步骤；agent 只能改“是否通过”，不能删改测试；必须端到端验证后才能标为通过。对应本账簿的「先写好的验收」和「防止验收被悄悄放宽」。
- OpenAI，[Harness engineering](https://openai.com/index/harness-engineering/)：仓库里的文档是唯一可信的来源；AGENTS.md 只做目录，指向更深的文档；有一份按产品区域和架构层打分、跟踪缺口的质量文档，以及定期扫描过时文档的 doc-gardening agent。对应「区域审查」，以及 AGENTS.md 只链接本账簿、不复制内容。
- OpenAI Cookbook，[Using PLANS.md](https://developers.openai.com/cookbook/articles/codex_exec_plans)：计划是活文档，写给对项目毫无了解的读者。对应「怎么确认」必须是任何人都能照着做的操作。
- Google SRE，[Reliable Product Launches](https://sre.google/sre-book/reliable-product-launches/) 与 [Launch Coordination Checklist](https://sre.google/sre-book/launch-checklist/)：用户可见的变化都算发布；清单里每一项都要能说明为什么需要，每条操作都要具体可行；清单定期复审。对应「维护」和「发布门槛怎么读」。
- Meta，[Holistic Configuration Management at Facebook](https://blog.acolyer.org/2015/10/16/holistic-configuration-management-at-facebook/)（SOSP 2015）：新代码先以关闭状态上线，用 Gatekeeper 逐步放开；配置当作代码，由校验器自动检查不变量。对应「功能开关后面的能力」和门禁的机器检查。
- NASA 系统工程的需求验证矩阵（[NASA NTRS](https://ntrs.nasa.gov/api/citations/20160003166/downloads/20160003166.pdf)）：每条需求标明验证方法（测试、分析、检查、演示）。对应「验证」列。SpaceX 的“每条需求都要带上提出它的人的名字”（Isaacson《Elon Musk》）对应「计划」列：每行都能追溯到工作包和背后的用户决定。没有找到 SpaceX 公开的需求矩阵原文。
- mdpro 的 `docs/feature-ledger.md`：五值状态、`Partial` 必须写限制、路径从仓库根写、同一次提交更新行，都沿用；单元格长成修复史的问题，用 150 字上限和 validation 链接避免。
