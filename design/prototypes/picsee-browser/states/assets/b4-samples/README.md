# B4 样图（原型，throwaway）

`prototype-first-launch-b4-final.html` 的 12 张散落相纸用的是这里的图。它们是 `../../../assets/` 下 12 张 Unsplash 原图的缩小副本，用来估算 App 打包这些样图要多大。原图没有改动。

生成命令（在 `design/prototypes/picsee-browser/` 下运行）：

```sh
for f in alley lakeside island temple hillside mountain lakehouse coast shore blue morning gate; do
  sips -s format jpeg -s formatOptions 75 -Z 480 assets/$f.jpg --out states/assets/b4-samples/$f.jpg
done
```

长边 480 px，JPEG 质量 75。相纸在 960×640 窗口里约 150×110 pt，在 Retina 屏上约 300×220 px，所以长边 480 px 留了裁切余量。

| 文件 | Unsplash 来源 | 像素 | 字节 |
|---|---|---|---:|
| alley.jpg | [wGjJ8A-4bik](https://unsplash.com/photos/wGjJ8A-4bik) | 320×480 | 62,165 |
| lakeside.jpg | [fpkbCzqSP5Y](https://unsplash.com/photos/fpkbCzqSP5Y) | 320×480 | 62,331 |
| island.jpg | [BjJP2TN8WoI](https://unsplash.com/photos/BjJP2TN8WoI) | 480×269 | 30,175 |
| temple.jpg | [Qeij_udWg_Q](https://unsplash.com/photos/Qeij_udWg_Q) | 480×320 | 50,906 |
| hillside.jpg | [OrIkJecH6_0](https://unsplash.com/photos/OrIkJecH6_0) | 480×320 | 66,038 |
| mountain.jpg | [VAYbkaSAdQw](https://unsplash.com/photos/VAYbkaSAdQw) | 480×270 | 22,416 |
| lakehouse.jpg | [i76g7kaM3Wo](https://unsplash.com/photos/i76g7kaM3Wo) | 480×320 | 57,894 |
| coast.jpg | [275oJc7KFCg](https://unsplash.com/photos/275oJc7KFCg) | 320×480 | 44,764 |
| shore.jpg | [wA5RE5AY9kE](https://unsplash.com/photos/wA5RE5AY9kE) | 320×480 | 36,284 |
| blue.jpg | [eJ9vmM8qNLM](https://unsplash.com/photos/eJ9vmM8qNLM) | 316×480 | 27,081 |
| morning.jpg | [9njZeiV5cxc](https://unsplash.com/photos/9njZeiV5cxc) | 320×480 | 32,865 |
| gate.jpg | [h9tMLl2DmD8](https://unsplash.com/photos/h9tMLl2DmD8) | 320×480 | 53,923 |
| **合计** | | | **546,842**（约 534 KiB） |

**建议的 App 打包预算：546,842 字节（约 534 KiB）**，12 张图。

许可：Unsplash License，可免费使用并打包进 App，不要求署名；不得原样出售照片，也不得汇编成与 Unsplash 竞争的服务。来源和原图 SHA-256 见 `../../../assets/sources.json` 与 `../../../ASSETS.md`。

这些文件只服务原型。是否把它们放进 App target 由用户和后续工作包决定；本目录不进 App。
