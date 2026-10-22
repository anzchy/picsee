# picsee 原生设计实施规范

版本0.1 · 2026-10-21 · 状态：**P0-08 原生 token、状态表面与 Debug 组件预览代码已建立，真机验证待完成**。

主设计规则仍由 [DESIGN.md](../../DESIGN.md) 决定；本目录将已确认的 C 布局转换为跨平台语义、组件契约和原生实现边界，不新增产品功能。

| 文档 | 解决的问题 |
| --- | --- |
| [TOKEN_MAPPING.md](TOKEN_MAPPING.md) | 哪些 CSS token 迁入原生、哪些留作兼容；points/pixels、字体、混色与尺寸 |
| [TOKEN_REGISTRY.json](TOKEN_REGISTRY.json) | 由现有 CSS 提取的语义映射清单；记录源文件 SHA256，可校验，非另一套手填颜色 |
| [COMPONENT_CONTRACTS.md](COMPONENT_CONTRACTS.md) | 组件输入、状态、键盘与可访问性、复用边界、对应 mockup 和阶段 |
| [NATIVE_MAPPING.md](NATIVE_MAPPING.md) | SwiftUI/AppKit 职责、外观/焦点/图像坐标的桥接、推荐代码归属与验收 |

约束：保留现有五个 production targets；PicseeDesignKit 是现有 UI target 内的逻辑分组，不新增第六个包。不把 JSX、CSS、静态 HTML 或全部遗留 token 机械翻译成 Swift。

变更路径：先修改主规范和 token 源，再更新本目录，最后实施原生组件。生成清单使用 `python3 scripts/export_native_design_tokens.py`；它只导出规格，不生成 Swift 或原生资源文件。
