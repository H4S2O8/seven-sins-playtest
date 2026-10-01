# 拼词对决 · Word Combat

双人轮流选词、编辑五张随从卡，在公开出招与应对后沿同一条时间轴结算的游戏原型。当前可与电脑对战。

**[在线试玩](https://h4s2o8.github.io/seven-sins-playtest/)**。`main` 更新后，GitHub Pages 发布 `pages/` 中的 Godot 网页版。

## 目录

| 目录 | 内容 |
| --- | --- |
| [`word-combat/godot/`](word-combat/godot/) | Godot 游戏源码、词库、编辑器、电脑对手和测试 |
| [`word-combat/`](word-combat/) | 规则、强组合与反制审计、参考结算器和模拟结果 |
| [`pages/`](pages/) | 当前可玩的 Web 导出，由 Pages 直接发布 |
| [`sin-squad-core/`](sin-squad-core/) | 旧版七罪暗队源码，仅作历史留存 |

本地运行和规则说明见 [Godot 原型文档](word-combat/godot/README.md)。当前仍是原型；强组合、反制与费用平衡尚在验证中。

要更新网页游戏，用 Godot 4.7.1 打开 `word-combat/godot/project.godot`，运行核心测试后将 Web Release 导出到仓库的 `pages/index.html`，提交源码和导出产物。`main` 上的 Pages 工作流会检查导出文件并发布。
