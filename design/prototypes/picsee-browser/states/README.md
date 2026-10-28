# picsee C 设计状态稿

这里是应随仓库提交的 **20份正式静态状态稿**，与上一级的交互原型分开维护。目录内容不依赖 `.stitch/`、登录凭据、Stitch CLI 或远程图片。

## 打开

项目根目录运行以下任一方式：

```sh
# 与交互原型使用同一服务
python3 -m http.server 4311 --bind 127.0.0.1 --directory design
# 地址：http://127.0.0.1:4311/prototypes/picsee-browser/states/index.html

# 单独预览状态稿，兼容原4313地址
python3 -m http.server 4313 --bind 127.0.0.1 --directory design/prototypes/picsee-browser/states
# 地址：http://127.0.0.1:4313/index.html
```

也可用 `npm run preview:prototype` / `npm run preview:states`。请经HTTP打开，索引需要读取本地manifest；不以双击file://作为验收方式。

## 素材分工

| 路径 | 作用 | 是否提交 |
| --- | --- | --- |
| `manifest.json` | 唯一页面目录：名称、文件、视口、来源类别及每页 HTML 的 SHA256 | 是 |
| `index.html` | 从manifest加载的浏览索引，不另维护一份页面列表 | 是 |
| 20个同名HTML | 正式静态状态；不声明按钮行为已实现 | 是 |
| `journeys.html` | 用户旅程图，是[计划 §1.6](../../../../docs/PICSEE_DEVELOPMENT_PLAN.md)旅程索引的视图（ADR-013），两者不一致时以 §1.6 为准；卡片只引用本目录的状态稿，不显示实现进度（进度看功能账簿）。不是状态稿，不进 `manifest.json`，由 `index.html` 链接 | 是 |
| `assets/images/`、`assets/manifest.json` | 13个按内容哈希命名的共享图片，替代95处重复base64 | 是 |
| `_ds/` | 设计系统编译后的运行时副本，由import工具同步 | 是，保证预览可直接运行 |
| `vendor/` | 固定版本React预览依赖；不是原生App依赖 | 是 |
| `provenance/stitch.json` | 原始Stitch screen IDs与打包前后哈希，不含凭据或签名下载URL | 是 |
| `_d_meta.json` | 设计系统绑定与资产索引 | 是 |

图片来源及摄影师链接见 [ASSETS.md](../ASSETS.md)。状态稿使用既有示例图及其缩略版；提取时保持原始图片字节，未改变构图。原型文件名、日期等演示信息不代表真实EXIF。

## 页内子情况

22、26 两页按 [ADR-014](../../../../docs/adr/0014-recoverable-folder-states-in-window.md) 把子情况放在同一页里，用查询参数切换；不带参数的地址就是主状态，`sha256` 固定的也是它的字节。按钮没有行为。

| 页面 | 不带参数 | 子情况 |
| --- | --- | --- |
| `empty-folder.html`（22-BD） | 这一层有子文件夹：子文件夹卡片、「包含子文件夹浏览」「选择其他文件夹…」，内容区可拖入 | `?case=no-subfolders` 最近打开的文件夹；`?drag=over` 拖入时的提示 |
| `permission-denied.html`（26-BC） | 授权失效：侧栏该文件夹变灰带 ⚠、子文件夹收起；「重新选择文件夹…」「选择其他文件夹…」 | `?cause=volume` 外接磁盘未连接；`?cause=missing` 找不到；`?cause=unknown` 原因分不清时的「无法访问此文件夹」；`?case=moved` 26M-C 同卷移动或改名后跟随，网格上方的提示条 |

两页都接受 `?theme=dark`。

## 维护

每页的 `sha256` 固定当前 HTML 的原始字节。修改正式状态稿后，先确认设计变更，再对该 HTML 运行 `shasum -a 256 <文件>`，将结果写入 `manifest.json` 对应条目；不要为绕过测试而重新固定哈希。`scripts/verify_design_catalog.js`（`playwright-cli run-code --filename=scripts/verify_design_catalog.js`，需先起 4311 与 4313 两个预览服务）检查 20 页的资源与布局、每页 HTML 与 `sha256` 一致、22/26 的子情况，以及 `journeys.html` 的入口表、只播放主路径、支线都有返回边、没有手写进度徽章、不引用原型文件和播放器焦点。

以 [主设计规范](../../../DESIGN.md)、[组件与原生映射](../../../picsee-ui-system/native/README.md) 和 [实施计划](../../../../docs/PICSEE_DEVELOPMENT_PLAN.md) 为依据。浏览器交互仍在 [viewer-v2.html](../viewer-v2.html)，完整状态稿不等于原生实现。

`.stitch/` 仅为本地捕获/生成/迁移工作目录，整体忽略。当前机器可保留 `.stitch/deliverables` 指向本目录的兼容链接；仓库和预览均不依赖这个链接。截图与运行检查输出属于 `evidence/`，无需复制到每份稿旁边。
