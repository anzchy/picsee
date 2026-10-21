# 语义 Token 与原生映射

2026-10-21。主规范：[DESIGN.md](../../DESIGN.md)。现有三份 CSS 为 Web 运行时数值源；[TOKEN_REGISTRY.json](TOKEN_REGISTRY.json) 只记录选定语义的源表达式和布局参考，不能反向修改 CSS。

## 1. 迁移规则

1. 原生只引入 picsee 实际需要的语义角色；名称表达用途，不把 `color-editor-bg`、底部编辑器 tabs 或 Tauri clearance 变成产品需求。
2. 同一角色只有一个原生入口，SwiftUI 与 AppKit 从同一资源/解析器取色。不把每个页面各自截取的颜色表拷进代码。
3. 当前 JSON 是 P0 的可核对输入；正式实施后原生资源与 CSS 各有适配层，修改需校验角色和值的一致性。未经校验不能宣称两个渲染器像素完全相同。
4. 颜色使用 sRGB 数值和显式 alpha；照片仍按自己的色彩管理管线处理，不能套 UI 调色板。

## 2. 颜色角色

| 原生语义名称（建议） | Web token | 用途 |
| --- | --- | --- |
| canvasBackground | --color-bg | 图片画布/主内容背景 |
| sidebarBackground | --color-surface | 安静侧栏和网格底栏 |
| popoverBackground | --color-panel | 自定义非系统浮层 |
| textPrimary / textSecondary | --color-text / --color-muted | 主要/次要文字 |
| divider / dividerSubtle | --color-border / --color-border-subtle | 结构/次级分隔线；不代替必要控件边界 |
| hoverBackground | --color-hover | 轻量悬停反馈 |
| accent / focusRing | --color-accent / --color-focus-ring | 强调与键盘焦点；语义独立，当前可同值 |
| selectionFill / selectionText | --color-accent-soft / --color-accent-text | 弱选中底色与对应文字 |
| primaryFill / primaryFillHover / onPrimary | --color-accent-fill / --color-accent-fill-hover / --color-on-accent | 主要动作 |
| controlBorder / inputBackground | --color-control-border / --color-input-bg | 自定义输入边界/背景 |
| error / errorFill / errorText | --color-danger / --color-danger-soft / --color-error-text | 错误，不作装饰 |
| scrim | --color-scrim | 真正模态场景的背景遮罩 |

系统 NSMenu、窗口控件、系统选择/焦点和可访问性高对比度外观优先遵循平台；不要为复刻网页边框而手绘系统窗口或劫持系统菜单材质。自定义组件再使用上述角色。

## 3. color-mix 与 alpha

- `color-mix(in srgb, text 10%, transparent)` 表示以该文字色提供10% alpha，再与实际背景合成；不要提前固定为只适用于白底的一种灰。
- 强调色与文字色的80%/20%等混合按指定 sRGB 空间计算；不能假设某个 AppKit 混色便利方法与 CSS 的色彩空间/alpha 行为完全一致。
- P0选择“预计算当前主题的确定性 sRGB 资源＋运行时 alpha”，或共享且经过用例验证的解析器。不要在视图绘制回调中解析 CSS 字符串。
- 对比度按合成后的实际邻接色测量；同时覆盖浅/深、hover/selected/focus。已有网页值不等于所有状态都通过原生可访问性验收。
- `--shadow-soft` 是 Web 效果配方，不直接导出为 NSShadow 参数。原生只保留“自定义浮层的一档克制层级”，在系统菜单/Popover上使用系统效果。

## 4. 数值、单位与系统指标

| 角色 | Web参考 | 原生处理 |
| --- | --- | --- |
| UI文字 | 12 / 13 / 14 / 16 CSS px | 同名角色以系统字体 points 起步，按实际字体度量/可访问性验证，不按 Retina 倍乘 |
| 数字/快捷键 | SF Mono / system monospace | 系统等宽字体或等宽数字；系统菜单使用自己的快捷键列 |
| 间距 | 4 / 8 / 12 / 16 / 24 | 对应 points 的布局角色；不是图像像素尺寸 |
| radius.inner / control / popover | 4 / 6 / 10 | 自定义组件的起始 points；系统控件圆角不硬覆盖 |
| 图标 | 16–18 | 系统符号/模板图形的起始 points；从共享 symbol catalog 取，不携带网页 SVG 代码作唯一实现 |
| iconButton hit area | 30×28 | 紧凑桌面起点；系统按钮允许更合适的尺寸，不把图形大小当命中区域 |
| 网格底栏 | 40 | 自定义状态/工具行起始高度，可随内容/可访问性调整 |
| 侧栏 | 当前196–220，范围160–320 | 自定义分栏起点；留足主内容；不要直接使用遗留 --sidebar-width-min:180 覆盖已确认的160下限 |
| 标题条 | Web38 | 仅是 mockup 参考；原生高度、红黄绿与安全区域由系统决定，不导出硬编码38pt标题栏 |
| Inspector | 当前约220 | 初始面板宽度，可按内容/窗口约束；元数据长值不越界 |
| 自动隐藏延迟 | 2500ms | Application状态机参数2.5s，可控时钟；不是组件内散落定时器 |
| 显隐短动效 | 150ms / Reduce Motion为0 | 原生用偏好驱动的短过渡；系统控件按平台；不可让焦点等动画结束才可用 |

布局使用 points。缩略图解码需求及1:1使用 view 的 backing 坐标转换：在2× backing环境，一张1600px宽的图在1:1时占约800pt；不因此把普通30pt按钮改成60pt。不能把 backing pixel 等同于显示器面板物理像素。跨屏时重算而不是缓存一次全局倍率。[Apple backingScaleFactor 说明](https://developer.apple.com/documentation/appkit/nswindow/backingscalefactor)建议常规情况优先使用 backing 坐标转换方法。

## 5. 兼容 token 不迁入首批原生组件

编辑器字体/宽度/行高、code/highlight、bottom-tabs、Tauri traffic-light clearance、运行状态徽标、未保存编辑器横条，以及未在 C 中实际使用的旧别名保留于现有 Web CSS 以兼容历史输出；**不进入原生导出白名单**。后续删 Web token 时另做消费者检查，不在本次破坏旧原型。

当前 JSON 不生成 Swift 枚举/ColorSet，不固化原生布局。P0-08 应检查导出源哈希、角色唯一性、两主题完整性、混色用例和布局/像素单位后再实现。
