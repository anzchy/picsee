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
| `assets/images/`、`assets/manifest.json` | 13个按内容哈希命名的共享图片，替代95处重复base64 | 是 |
| `_ds/` | 设计系统编译后的运行时副本，由import工具同步 | 是，保证预览可直接运行 |
| `vendor/` | 固定版本React预览依赖；不是原生App依赖 | 是 |
| `provenance/stitch.json` | 原始Stitch screen IDs与打包前后哈希，不含凭据或签名下载URL | 是 |
| `_d_meta.json` | 设计系统绑定与资产索引 | 是 |

图片来源及摄影师链接见 [ASSETS.md](../ASSETS.md)。状态稿使用既有示例图及其缩略版；提取时保持原始图片字节，未改变构图。原型文件名、日期等演示信息不代表真实EXIF。

## 维护

每页的 `sha256` 固定当前 HTML 的原始字节。修改正式状态稿后，先确认设计变更，再对该 HTML 运行 `shasum -a 256 <文件>`，将结果写入 `manifest.json` 对应条目；不要为绕过测试而重新固定哈希。

以 [主设计规范](../../../DESIGN.md)、[组件与原生映射](../../../picsee-ui-system/native/README.md) 和 [实施计划](../../../../docs/PICSEE_DEVELOPMENT_PLAN.md) 为依据。浏览器交互仍在 [viewer-v2.html](../viewer-v2.html)，完整状态稿不等于原生实现。

`.stitch/` 仅为本地捕获/生成/迁移工作目录，整体忽略。当前机器可保留 `.stitch/deliverables` 指向本目录的兼容链接；仓库和预览均不依赖这个链接。截图与运行检查输出属于 `evidence/`，无需复制到每份稿旁边。
