# iMaccy

> A Maccy-inspired clipboard workspace for prompts on macOS.

`iMaccy` 是一个基于 [p0deje/Maccy](https://github.com/p0deje/Maccy) 继续演进的 macOS 剪贴板工具项目。
当前仓库已经保留上游 Maccy 代码基础；**本次提交先补齐产品设计、交互设计、技术改造方案与 UI 设计稿，暂不直接实现新功能。**

## 设计目标

在保留 Maccy 轻量、克制、键盘优先、原生 macOS 体验的前提下，为高频 Prompt 使用场景增加：

- 标签化管理
- 默认 `Prompt` 分类
- `Prompt` 分类下的子书签 / 子分类
- 常用 Prompt 收藏
- 右键将任意剪贴板内容移动到 `Prompt` 分类
- 更适合 Prompt 检索、归档、复用的组织结构

## 设计文档

- [`docs/spec/imaccy-design-spec.md`](./docs/spec/imaccy-design-spec.md)：完整产品与技术设计方案
- [`docs/spec/imaccy-implementation-plan.md`](./docs/spec/imaccy-implementation-plan.md)：分阶段改造计划与任务拆分
- [`docs/ui/imaccy-wireframe.svg`](./docs/ui/imaccy-wireframe.svg)：UI 设计图（SVG）
- [`docs/ui/imaccy-wireframe.png`](./docs/ui/imaccy-wireframe.png)：UI 设计图预览（PNG）
- [`docs/ui/notes.md`](./docs/ui/notes.md)：UI 草图说明

## 设计图预览

![iMaccy UI Wireframe](/Users/zscc.in/Desktop/AI/imaccy/docs/ui/imaccy-wireframe.png)

## 设计原则

1. **尽量像 Maccy**：默认体验依旧是打开即搜、上下选择、回车复制/粘贴。
2. **Prompt 是一等公民**：Prompt 不只是普通剪贴板记录，而是可归档、可收藏、可复用的知识资产。
3. **组织能力只在需要时显露**：轻用户看到的仍是极简列表，重用户可以使用标签、子书签、常用 Prompt。
4. **先改造，不重写**：优先沿用 Maccy 的 `FloatingPanel + SwiftUI + SwiftData` 架构，降低偏移成本。

## 本阶段产出

- 完整产品设计方案
- 技术改造边界与模块拆分
- UI 设计图 / 线框稿
- 分阶段实施计划

## 下一步建议

1. 先完成 Prompt 域的数据模型与过滤层改造。
2. 再补 `右键移动到 Prompt`、标签、子书签管理。
3. 最后补设置页、迁移逻辑、搜索语法和可用性打磨。

## Upstream Baseline

本仓库继续基于上游 Maccy：

- Upstream: [p0deje/Maccy](https://github.com/p0deje/Maccy)
- Current repo: [izscc/iMaccy](https://github.com/izscc/iMaccy)

实现阶段会尽量在不破坏 Maccy 原始历史主链路的前提下，增加独立的 Prompt Library 能力。
