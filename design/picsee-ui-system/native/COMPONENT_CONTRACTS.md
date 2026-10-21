# C 方案组件契约

版本0.1 · 2026-10-21。对应 [主规范](../../DESIGN.md)、[20页索引](../../prototypes/picsee-browser/states/index.html)。以下原生名称和输入是建议接口，不是已存在的 Swift 类型。当前仅有 IconButton/Keycap/NavRow 三个 Web primitive；不新增虚假的原生实现状态。

## 1. 共同约束

- 组件接收展示状态和命令回调，不直接解码、枚举目录、操作缓存或请求文件权限。
- 命令带明确目标身份/快照；组件不自己查询“全局当前图片”。Session/CommandRouter 为状态所有者。
- default、hover、pressed、selected、keyboard-focused、disabled分开描述；`selected`不代替焦点。异步busy/error属于数据展示，不用无限spinner隐藏错误。
- 用户可用的动作才进入焦点与辅助技术树。自定义图标按钮有名称，动态计数有可读文本，不靠颜色或 tooltip 单独解释动作。
- 同一组件在浅深主题共用结构与状态，不分别实现一份 Light/Dark 业务视图。

## 2. 基础 primitive

| 契约 | 输入/输出（概念） | 样式与状态 | 原生方向 / 阶段 |
| --- | --- | --- | --- |
| IconCommandButton | command、accessibleLabel、symbolRole、enabled、pressed、action | 图形16–18、命中约30×28；focus ring独立于pressed；disabled禁止激活 | SwiftUI Button/ButtonStyle，必要时NSButton；P0-08/P1 |
| ShortcutHint | command显示文本、可选accessibilityDescription | 12pt等宽、轻量背景/边界；不是可点击按钮 | SwiftUI Text；NSMenu使用系统key equivalent；P0-08 |
| FolderNavigationRow | nodeID、name、symbolRole、optionalCount、selected、expanded、enabled；onSelect/onExpand | 行高起点32；名称截断但完整可读；选中弱底色；展开与选择分开 | SwiftUI目录/导航行；必要树形宿主由功能层选择；P0-08/P3 |

验收：图标/文字有正确label；键盘与鼠标只触发一次命令；不可用项无法激活；重复行使用稳定nodeID；符号缺失有可解释回退；主题变化不改变选择。

## 3. 领域视觉与组合规范

下列对象是可复用视觉或功能组合契约，不意味着把完整应用状态机塞进设计系统。

### ThumbnailItemVisual（11/12/32，P3-01/02/09）

输入：ItemID、对应Revision/呈现绑定标识、预览载荷/占位/失败、filename、showFilename、fitMode、isSelected、isCurrent、hasKeyboardFocus、favorite。输出：选择/打开/上下文菜单意图。

- AppKit NSCollectionViewItem绘制/布局，功能层提供图片订阅；复用时立即解除旧绑定，只接受匹配ItemID与代次的载荷。
- 单选是细边框＋文件名弱底色；多选可有小勾选标记；当前项/焦点不靠“所有选中边框都更亮”表达。
- 完整适应/裁剪预览是显式偏好；不改变实际文件内容。失败项保留文件身份和恢复路径。
- 验收：3项选择只有1个当前项，滚动复用不串图，长文件名不挤出相邻项；菜单目标在打开时固定。

### ViewerControlGroup（13/14/28，P1-08）

输入：可见性/交互锁定、当前位置与序列边界、文件名、缩放模式、各命令enabled状态。输出：命令与pointer/focus交互事件。

- 左下入口、中下导航、右下缩放；位置由功能层的C布局宿主管理，不由按钮各自读屏幕尺寸。
- 不持有隐藏计时器；组件将hover/focus/menu活动上报Session。隐藏时取消命中与键盘/辅助技术访问，恢复时先可见再聚焦。
- 系统窗口控件独立于该组合，不能作为一组普通图标隐藏掉。
- 验收：13与14的可见控件数量有真实区别；Tab可唤回；首尾禁用正确；输入/菜单不重复触发翻图。

### Filmstrip（33，P2-06）

输入：有序预览IDs、currentID、轻量缩略图展示、filename/position/total、展开偏好。输出：selectID、previous/next、close等意图。

- 功能层实现虚拟化与请求调度；复用Thumbnail视觉规则，缩略图不承担全图加载。
- 展开后由胶片条拥有唯一的文件名/序号/翻图组，撤下另一套中部导航；左下与右下工具不重叠，主图适应尺寸不因展开而额外缩小。
- 默认收起；展开是用户偏好，不是每次切图都重置。可滚动且当前项可见。
- 验收：选中项可定位、导航按钮各一组；12张与5000张目录使用同一有界机制；窄窗不遮住当前焦点。

### InspectorInfoRow / InspectorPanel（16/34，P3-13/P5-01）

行输入：本地化label、value / loading / unknown / error、可复制性。Panel输入：当前item身份、行集合、favorite状态。输出：关闭/收藏等命令。

- SwiftUI标签/值行，长值换行或提供完整访问方式，数值按适当等宽规则；面板不自己读取EXIF。
- 同一结构随外观解析颜色；未知显示“—”而非虚构ISO、焦距或文件大小。
- 关闭后将焦点恢复到合理入口；非模态面板不强制困住Tab。
- 验收：异步结果只属于当前项；权限失效/读失败可表达；浅深切换不复制状态。

### EmptyStateContent（21–26，P1/P2/P3）

输入：typed状态、title/message、可选主要/次要命令、进度形态、已有上下文。输出：命令意图。

- SwiftUI内容组合，安静留白与清晰下一步；每种错误保持文件/目录上下文，空结果提供清除筛选。
- 未得总数使用不定进度；拖入说明是文字而不是无效按钮；无打开目标时禁用无意义工具。
- 验收：首次打开、空目录、筛选空、扫描、损坏图、授权失效可区分；不以错误态阻断关闭/换目录。

### ImageContextMenuSpec（31，P3-12）

输入：不可变TargetContext、选择范围、授权/文件存在性、可用命令。输出：带同一目标的命令。

- 使用NSMenu与系统菜单键盘行为；菜单项顺序：快速查看、在访达中显示、拷贝路径、收藏、图片信息。目录/多选菜单不复用错误的单图语义。
- 只声明已实现命令和快捷键；没有可用目标时禁用。系统菜单材质允许不同于Web静态圆角。
- 验收：右键未选中项、菜单打开后目标被移除、Esc恢复焦点、屏幕边缘定位；单次激活不同时触发全局Space/方向键。

### DisplayPreferenceControls / SelectionSummary（15/32，P1-09/P3-09/11）

- 控件读取同一DisplayPreferences，修改通过应用用例提交；使用SwiftUI原生Picker/Toggle/Slider及清晰label。系统/浅/深三态、显示文件名、缩略图模式、密度、工具常驻保持语义一致。
- SelectionSummary接收选择数量、总数、可选真实汇总；不计算目录、不猜测总大小。应用选择Reducer负责集合/当前项/锚点和Space预览集合。
- 验收：窗口/重启恢复按策略一致；过滤后计数真实；不增加永久批量工具横栏。

## 4. 复用边界与完成定义

设计系统持有视觉角色、尺寸起点、可访问名称规则、组件状态表达。Application持有选择、偏好、命令、显隐状态和计时；Infrastructure持有文件/图像/缓存/权限；功能宿主持有窗口布局、viewport与滚动协调。

P0-08交付的原生组件预览应覆盖两主题、全部基础状态、长文案及Reduce Motion；P0-09验证焦点/命令状态；P1/P2/P3分别验收上述组合。截图、交互测试和VoiceOver实机结果分开记录，不能用Web组件可渲染替代原生完成定义。
