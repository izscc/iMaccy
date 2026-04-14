# iMaccy Implementation Plan

## 1. 改造原则

- 先做数据层，再做 UI
- 先做最小闭环，再做扩展搜索与设置页
- 每一步都保留可回退路径
- 不破坏现有 Maccy 的复制/粘贴主流程

---

## 2. 分阶段路线图

### Phase 0 — 仓库初始化与品牌替换

- 项目名改为 `iMaccy`
- 替换 Bundle 标识与显示名
- 增加设计文档与品牌素材占位

**验收标准**
- 仓库可独立存在
- 文档和设计稿齐全

### Phase 1 — 数据模型改造

- 新增 `PromptItem`
- 新增 `PromptCategory`
- 新增 `PromptTag` 与 `PromptItemTagLink`
- 默认注入 `Prompt` 根分类

**验收标准**
- 新老历史记录都能被正常读取
- 首次启动后存在系统 `Prompt`

### Phase 2 — 列表筛选状态

- 新增 `FilterStateStore`
- 支持：全部 / Prompt / 常用 / 已固定
- 支持标签过滤、子书签过滤

**验收标准**
- 同一份历史记录能在不同过滤条件下稳定显示

### Phase 3 — 条目组织动作

- 右键菜单新增 Prompt/标签操作
- 详情面板新增归档与收藏操作

**验收标准**
- 用户可通过右键把条目移动到 Prompt
- 用户可选择子书签
- 用户可设为常用 Prompt

### Phase 4 — Prompt 管理视图

- 左侧组织视图 / 轻侧栏
- 子书签管理
- 标签管理

**验收标准**
- 用户可以创建、重命名、删除子书签
- 用户可以维护标签

### Phase 5 — 体验打磨

- 搜索语法增强
- 最近使用子书签
- 批量归类
- 动画与细节 polish

**验收标准**
- 重度 Prompt 用户能够高效归档与复用

---

## 3. 建议新增文件

### Models
- `Models/LibraryNode.swift`
- `Models/ItemTagLink.swift`

### Observables
- `Observables/LibraryStore.swift`
- `Observables/FilterStateStore.swift`
- `Observables/PromptOrganizer.swift`

### Views
- `Views/LibrarySidebarView.swift`
- `Views/FilterSegmentView.swift`
- `Views/TagChipView.swift`
- `Views/PromptInspectorView.swift`
- `Views/PromptBookmarkPickerView.swift`
- `Views/ItemContextMenuModifier.swift`

### Settings
- `Settings/LibrarySettingsPane.swift`

---

## 4. 对现有 Maccy 的最小改动点

- `Storage.swift`：扩展 model container
- `ContentView.swift`：增加轻量筛选入口与 Prompt 入口
- `HistoryItemView.swift`：增加 row-level context menu 挂载点
- `SlideoutContentView.swift`：增加 Prompt 操作区
- `AppState.swift`：挂载 Prompt 相关 store 与设置页
- 新增独立 Prompt 模块文件（而不是重写 History 主链路）

---

## 5. 验证清单

- [ ] 不影响原有复制/粘贴主链路
- [ ] 不明显降低打开弹窗速度
- [ ] Prompt 归档路径少于 2 次点击
- [ ] 常用 Prompt 一眼可识别
- [ ] 标签与子书签不会造成列表过度拥挤
- [ ] 旧数据可正常迁移

---

## 6. 推荐实施顺序

1. 先只做 `Prompt` 根分类 + `PromptItem` + Favorite Prompt
2. 再做子书签
3. 再做 Prompt 域标签
4. 最后做高级搜索语法

这个顺序最稳，因为它先把最重要的用户价值闭环打通。
