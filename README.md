# 吞噬进化：深渊之种

3D 单机深海「吞噬进化」游戏。首发目标 Steam（PC），一人开发。方案见 [docs/design-bible/09-3D方案.md](docs/design-bible/09-3D方案.md)。

- `prototype/feel/`：2D 手感原型（参考用：手感参数会沿用到 3D 版），浏览器直接打开 `index.html` 就能玩
- `prototype/visual-2.5d/`：2.5D 画面演示（参考用，已决定做完整 3D）
- `docs/`：设计文档，入口见 [docs/README.md](docs/README.md)

`prototype/feel/game.html` 是原型源码（不含 html 外壳），`index.html` 由它加上外壳生成。改源码后重新生成：

```sh
(echo '<!doctype html>'; echo '<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>'; cat prototype/feel/game.html; echo '</body></html>') > prototype/feel/index.html
```
