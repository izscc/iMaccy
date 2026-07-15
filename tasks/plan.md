# Implementation Plan: iMaccy 稳定性、性能与 Prompt 工作台升级

## Overview

本轮升级分为三条主线：先修复窗口失焦/外部点击/粘贴目标等高风险交互，再治理 Prompt 数据完整性与主线程性能，最后完成 Prompt 新建编辑、筛选、批量管理和自适应 UI。保持现有 `History` 与独立 `Prompt Library` 的领域边界，不重写稳定的剪贴板主链路。

## 审查结论与优先级

### P0：应先修复

- `FloatingPanel.resignKey()` 使用固定 50ms 延迟，未取消旧任务，也未在执行时检查 `isKeyWindow`；快速失焦后重新聚焦仍可能被旧任务关闭。`ContentView` 的 scene phase 延迟判断存在相同竞态。
- `shouldRemainPresentedAfterResign` 依赖全局 `NSApp.modalWindow/alertWindow`，无关弹窗也可能阻止主面板关闭，弹窗结束后又不会重新判定。
- 当前鼠标激活实际未使用 `selectFromPointer`/`selectPromptFromPointer`，焦点恢复代码成为死路径，鼠标粘贴可能发往错误窗口。
- Prompt 删除不会清理 `PromptItemTagLink`，会形成孤儿关联。
- 标签允许空格和 `#`，但 `#标签` 搜索解析不支持这些名称；category/tag 写入也允许无效 UUID。
- Prompt 详情中的“复制 Prompt”调用 `selectPrompt`，可能关闭窗口并自动粘贴，动作语义错误。

### P1：性能与体验

- Prompt 标签筛选和行摘要反复扫描全部 link，复杂度接近平方级；根分类查询甚至可能进入行渲染路径。
- 批量标签逐条 `save + load`，随后 `AppState.refreshPromptData` 再全量加载。
- `History.add` 每次复制会全表 fetch 查重，并反复 `filter` 统计容量；`Throttler` 的时间差计算会让首次调用也延迟。
- `Storage.size` 为获取文件大小读取整个 SQLite 文件。
- Prompt 不能直接新建、编辑标题/正文或复制副本；根目录不能单独筛选，多选缺少 Shift 范围选择、`⌘A`、Undo。
- `PromptWorkspaceView.swift` 超过千行，固定三栏宽度和 980pt 最小宽度不利于维护与小屏体验。

## Architecture Decisions

- 引入可测试的 `PanelDismissalCoordinator` 与纯 `WindowDismissalPolicy`，统一窗口生命周期，不再在 View 和 NSPanel 中各自维护延迟状态。
- 将条目动作明确为 `select`、`copy`、`paste`，并携带 `.keyboard/.pointer/.detailButton` 来源；复制和粘贴不再共用一个方法。
- Prompt 数据读写收口到单一 repository/snapshot 层。写操作返回结果或抛出领域错误，UI 不直接依赖静默 `try?`。
- 建立 `PromptSnapshot` 索引：`categoryByID`、`tagByID`、`tagIDsByPromptID`、`tagsByPromptID`、缓存的 visible items。
- Prompt UI 使用自适应 split layout；先拆模块再加新功能，避免继续膨胀单文件。
- 所有性能优化先采集基线，再用 500/5,000 条 History 和 100/1,000/10,000 条 Prompt 数据集复测。

## Dependency Graph

```text
反馈回路与基线
├── 窗口策略测试 → 失焦竞态修复 → 鼠标/键盘动作统一
├── Prompt 完整性 → Prompt 快照索引 → 批量事务与搜索性能
└── Prompt 动作语义 → 自适应 UI → 编辑闭环 → 筛选/批量/无障碍
```

## Task Details

### Task 1: 建立可重复的基线与诊断入口

**Description:** 配置完整 Xcode Developer Directory，记录当前 build/test 结果；加入窗口事件、首次打开、History/Prompt 加载与搜索耗时的 `os_signpost`，不改变业务行为。

**Acceptance criteria:**
- [ ] 有一条可重复执行的全量测试命令和一条窗口 UI 回归命令。
- [ ] 能记录 cold launch、首次弹窗、搜索和批量标签耗时。
- [ ] 调试日志不写用户 Prompt 正文。

**Verification:** `xcodebuild test -project iMaccy.xcodeproj -scheme iMaccy -destination 'platform=macOS'`

**Dependencies:** None
**Files likely touched:** `iMaccy.xctestplan`, `Maccy/DebugPasteLog.swift`, 新增 `Maccy/Diagnostics.swift`
**Estimated scope:** M

### Task 2: 提取窗口关闭策略并锁定竞态

**Description:** 将“何时因 resign key 关闭”提取成纯策略和可取消调度器，先写失败测试覆盖外点关闭、30ms 内重新聚焦、所属 sheet、无关 alert 和字符面板。

**Acceptance criteria:**
- [ ] `resign → regain key → timeout` 不关闭。
- [ ] 真正点击其他应用/桌面后关闭。
- [ ] 仅面板所属 sheet/popover/字符面板可暂缓关闭。

**Verification:** 运行新增 `WindowDismissalPolicyTests`。

**Dependencies:** Task 1
**Files likely touched:** 新增 `Maccy/WindowDismissalPolicy.swift`, 新增 `MaccyTests/WindowDismissalPolicyTests.swift`
**Estimated scope:** S

### Task 3: 统一 FloatingPanel 与 scene phase 生命周期

**Description:** 在 `didBecomeKey` 时取消 pending close，在延迟执行时再次检查 `isKeyWindow`；由一个 coordinator 同步 `isPresented`、高亮和 scene phase，移除 `ContentView` 的重复 50ms 逻辑。

**Acceptance criteria:**
- [ ] 快速开关、sheet 收回、状态栏重复点击不出现“刚打开又关闭”。
- [ ] 外点后 panel、scene phase、status item 高亮状态一致。
- [ ] 无关 modal/alert 不再永久阻止关闭。

**Verification:** 单元测试 + UI 手测矩阵：热键、状态栏、桌面、其他 App、sheet、context menu、emoji picker。

**Dependencies:** Task 2
**Files likely touched:** `Maccy/FloatingPanel.swift`, `Maccy/Views/ContentView.swift`, `Maccy/Observables/Popup.swift`, `Maccy/WindowDismissalPolicy.swift`
**Estimated scope:** M

### Task 4: 统一选择、复制、粘贴与焦点恢复

**Description:** 引入明确的 item action/activation source。键盘和鼠标粘贴都必须先记住原应用、复制、关闭面板、恢复目标应用，再在目标激活后发送粘贴；“复制”绝不自动粘贴。

**Acceptance criteria:**
- [ ] History 与 Prompt 的 copy/paste 行为遵守同一设置和快捷键规则。
- [ ] TextEdit 等目标中，鼠标和 Enter 粘贴均进入原输入框。
- [ ] Prompt 详情“复制”只写剪贴板，不关闭窗口、不增加错误的粘贴行为。

**Verification:** 新增 action coordinator 单测；UI 测试覆盖热键/状态栏打开及 pointer/keyboard 激活。

**Dependencies:** Task 3
**Files likely touched:** `Maccy/Observables/AppState.swift`, `Maccy/Observables/History.swift`, `Maccy/Observables/Popup.swift`, `Maccy/Views/PromptWorkspaceView.swift`, `Maccy/Views/HistoryItemView.swift`
**Estimated scope:** M

### Task 5: 修复 Prompt 数据完整性并执行一次性清理

**Description:** 删除 Prompt 时同步删除 tag links；写入前验证 category/tag；启动迁移清理孤儿 link 和悬空 category/tag 引用，并让关键保存错误可观察。

**Acceptance criteria:**
- [ ] 单条/批量删除后关联表无孤儿。
- [ ] 无效 UUID 被领域错误拒绝。
- [ ] 旧数据库清理幂等，重复运行不改变正确数据。

**Verification:** 新增 `PromptIntegrityTests`，覆盖损坏 fixture 和迁移重跑。

**Dependencies:** Task 1
**Files likely touched:** `Maccy/Models/PromptModels.swift`, `Maccy/Observables/PromptStores.swift`, `Maccy/Storage.swift`, 新增 `MaccyTests/PromptIntegrityTests.swift`
**Estimated scope:** M

### Task 6: 明确搜索、重复项与使用统计语义

**Description:** 抽出 `PromptSearchParser`；决定标签名称限制或实现 `#"多词标签"`；未知标签返回可展示状态。归档不计入 `usageCount`，增加 `lastUsedAt`，并确定 duplicate copy 的后续匹配规则。

**Acceptance criteria:**
- [ ] Unicode、空格、`#`、未知标签均有确定结果和错误提示。
- [ ] `usageCount` 只在用户实际 copy/paste 时增长。
- [ ] 允许副本后，重复更新目标不会随机选择。

**Verification:** 新增 parser、duplicate、usage 单元测试。

**Dependencies:** Task 5
**Files likely touched:** `Maccy/Models/PromptModels.swift`, `Maccy/Observables/PromptStores.swift`, 新增 `Maccy/PromptSearchParser.swift`, 新增 `MaccyTests/PromptSearchParserTests.swift`
**Estimated scope:** M

### Task 7: 建立 PromptSnapshot 索引与缓存筛选结果

**Description:** 加载后一次性构建 category/tag/link 索引；`visiblePromptItems` 由输入状态变化时重算，不在多个 View getter 中重复全量过滤；搜索增加 100–150ms debounce。

**Acceptance criteria:**
- [ ] 行渲染不触发数据库 fetch。
- [ ] tag/category 查找为 O(1)，筛选不再逐项扫描全部 links。
- [ ] 1,000 条 Prompt 搜索与切换标签无明显 UI 卡顿。

**Verification:** `XCTest.measure` 比较优化前后 100/1,000/10,000 条数据。

**Dependencies:** Tasks 5–6
**Files likely touched:** `Maccy/Observables/PromptStores.swift`, `Maccy/Observables/AppState.swift`, 新增 `Maccy/Models/PromptSnapshot.swift`, 新增 `MaccyTests/PromptPerformanceTests.swift`
**Estimated scope:** M

### Task 8: 将批量写操作改为单事务

**Description:** 批量移动、加/移标签、收藏、删除在一个 context transaction 中计算差集，只保存一次并生成一次新 snapshot；移除操作内外重复 `load()`。

**Acceptance criteria:**
- [ ] N 条批量操作最多一次 save 和一次 snapshot refresh。
- [ ] 操作失败时不留下部分成功状态。
- [ ] 选择状态在操作后保持可预测。

**Verification:** repository spy/计数测试 + 1,000 条批量性能测试。

**Dependencies:** Task 7
**Files likely touched:** `Maccy/Observables/PromptStores.swift`, `Maccy/Observables/AppState.swift`, `MaccyTests/PromptPerformanceTests.swift`
**Estimated scope:** M

### Task 9: 优化 History 与通用热路径

**Description:** 修正 `Throttler` 时间差；History 容量计数和查重优先使用内存索引/受限查询，避免每次复制全表 fetch；获取数据库大小改用文件 metadata。

**Acceptance criteria:**
- [ ] 首次 search 输入按设计立即或在明确 debounce 后执行。
- [ ] 新复制不再扫描整个数据库；容量裁剪为近 O(1)。
- [ ] `Storage.size` 不读取完整 SQLite 内容。

**Verification:** `ThrottlerTests`、History 500/5,000 条 add 基准、内存分配对比。

**Dependencies:** Task 1
**Files likely touched:** `Maccy/Throttler.swift`, `Maccy/Observables/History.swift`, `Maccy/Storage.swift`, 新增 `MaccyTests/PerformanceTests.swift`
**Estimated scope:** M

### Task 10: 分阶段启动与首次弹窗加载

**Description:** 将启动必须项与 Prompt 管理数据分开；History 首屏优先，Prompt 数据按默认 scope 或首次进入加载。避免 animation key 对完整数组反复 map，并限制主线程上的同步 fetch/图片处理。

**Acceptance criteria:**
- [ ] 默认 History 冷启动不等待 Prompt 全量加载。
- [ ] 首次弹窗达到可交互状态的时间有可测下降。
- [ ] 切换 Prompt 时显示短暂 loading/错误状态，而不是空白或静默失败。

**Verification:** signpost 基线对比，至少重复 5 次取中位数。

**Dependencies:** Tasks 7 and 9
**Files likely touched:** `Maccy/Views/ContentView.swift`, `Maccy/Observables/AppState.swift`, `Maccy/Observables/History.swift`, `Maccy/Diagnostics.swift`
**Estimated scope:** M

### Task 11: 拆分并自适应 Prompt Workspace

**Description:** 将 Sidebar、List/Row、Inspector、Bulk Bar、Sheets 拆分为独立文件；用可折叠、自适应 split layout 替代固定 220/300pt 三栏，保留 macOS 原生轻量感。

**Acceptance criteria:**
- [ ] 800–1,400pt 可用宽度下无控件截断或横向溢出。
- [ ] 小宽度可隐藏 Inspector，选择项和筛选状态不丢失。
- [ ] 单个主要 View 文件控制在可维护规模。

**Verification:** SwiftUI previews + 三种窗口尺寸截图回归。

**Dependencies:** Tasks 4 and 7
**Files likely touched:** `Maccy/Views/PromptWorkspaceView.swift`, 新增 `PromptSidebarView.swift`, `PromptListView.swift`, `PromptInspectorView.swift`, `PromptSheets.swift`
**Estimated scope:** M

### Task 12: 完成 Prompt 新建、编辑与复制副本闭环

**Description:** 提供新建 Prompt、编辑标题/正文、另存副本、保存/取消和未保存保护；复制到剪贴板、粘贴并关闭是两个明确按钮。

**Acceptance criteria:**
- [ ] 用户无需先制造 History 项即可新建 Prompt。
- [ ] 编辑失败不会丢失原内容；关闭未保存编辑有提示。
- [ ] duplicate、copy、paste 的统计和焦点语义正确。

**Verification:** repository 单测 + 新建/编辑/取消/副本 UI 测试。

**Dependencies:** Tasks 6, 8, 11
**Files likely touched:** `Maccy/Observables/PromptStores.swift`, `Maccy/Observables/AppState.swift`, `Maccy/Views/PromptInspectorView.swift`, 新增 `Maccy/Views/PromptEditorView.swift`, `MaccyTests/PromptEditorTests.swift`
**Estimated scope:** M

### Task 13: 升级筛选、排序与列表信息层级

**Description:** 区分“全部 Prompt”与“Prompt 根目录”；加入 active filter chips、清除全部、分类/标签计数、未知标签提示和排序选项。列表使用星标图标、正文摘要和区分明显的分类/标签样式。

**Acceptance criteria:**
- [ ] 根目录可单独筛选，当前组合始终可见且可一键清除。
- [ ] 支持最近使用、使用频率、最近更新、标题排序。
- [ ] 空状态准确说明是无数据、无匹配还是未知标签。

**Verification:** filter/sort 单测 + 各空状态 snapshot/UI 测试。

**Dependencies:** Tasks 6–7 and 11
**Files likely touched:** `Maccy/Observables/AppState.swift`, `Maccy/Views/PromptSidebarView.swift`, `Maccy/Views/PromptListView.swift`, `Maccy/Settings/PromptSettingsPane.swift`, `MaccyTests/PromptFilterTests.swift`
**Estimated scope:** M

### Task 14: 完善多选、批量操作与撤销

**Description:** 支持 Shift 范围选择、`⌘A`、Esc 清除；多选时 Delete 进入批量删除流程。批量标签显示三态，工具栏只保留主要动作，其余放入 `…`，破坏性操作提供 Undo。

**Acceptance criteria:**
- [ ] 键盘和鼠标选择符合 macOS 惯例。
- [ ] 多选 Delete 不再只删除 lead item。
- [ ] move/tag/favorite/delete 可撤销或有明确确认与结果反馈。

**Verification:** selection reducer 单测 + 键盘 UI 测试。

**Dependencies:** Tasks 8 and 11
**Files likely touched:** `Maccy/Observables/AppState.swift`, `Maccy/Views/KeyHandlingView.swift`, `Maccy/Views/PromptListView.swift`, `Maccy/Views/PromptWorkspaceView.swift`, `MaccyTests/PromptSelectionTests.swift`
**Estimated scope:** M

### Task 15: 本地化、无障碍与发布回归

**Description:** 将 Prompt 硬编码中文迁入本地化资源；增加稳定 accessibility identifiers/labels/actions；建立完整回归矩阵和性能阈值，清理失效字段、死代码和临时日志。

**Acceptance criteria:**
- [ ] Prompt 关键流程可由 UI 测试稳定定位。
- [ ] VoiceOver 可读出选择、收藏、分类、标签和按钮用途。
- [ ] 全量测试、SwiftLint、Debug/Release build 通过，性能不低于基线。

**Verification:**
- `xcodebuild test -project iMaccy.xcodeproj -scheme iMaccy -destination 'platform=macOS'`
- `swiftlint lint --config .swiftlint.yml`
- 按 `docs/release.md` 做 Release/Distribution smoke check。

**Dependencies:** Tasks 3–14
**Files likely touched:** `Maccy/*lproj`, `MaccyUITests/MaccyUITests.swift`, `.swiftlint.yml`, 相关 Prompt Views
**Estimated scope:** M（应按语言与测试拆成多个提交）

## Checkpoints

### Checkpoint A — Tasks 1–4：窗口与核心动作

- [ ] 外点关闭、快速复焦、sheet/popover、emoji picker 行为稳定。
- [ ] 鼠标/键盘 copy/paste 都命中原应用。
- [ ] Prompt “复制”不再触发粘贴或关闭。

### Checkpoint B — Tasks 5–10：数据与性能

- [ ] 无孤儿记录和悬空引用。
- [ ] 1,000 条 Prompt 搜索、批量标签达到设定阈值。
- [ ] History 首次弹窗和持续复制无明显回归。

### Checkpoint C — Tasks 11–15：Prompt 产品闭环

- [ ] 新建、编辑、整理、搜索、复制、粘贴、批量操作端到端可用。
- [ ] 小屏、自适应、本地化、VoiceOver 和 UI 自动化通过。
- [ ] 具备可发布的回归证据。

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| NSPanel 焦点行为依赖 AppKit 时序 | High | 纯策略单测 + 真机 UI 测试；一次只改一个生命周期变量 |
| SwiftData schema 变化损坏现有数据 | High | 先做手工完整性清理；迁移幂等；备份 fixture 验证 |
| 为性能引入双重状态源 | High | snapshot 为唯一读模型，写操作统一经 repository |
| UI 重构与逻辑修复相互干扰 | Medium | 先完成 Tasks 1–10，再拆 UI；每阶段保持可运行 |
| 鼠标单击/双击产品语义不清 | Medium | 默认采用“History 保持快速激活，Prompt 单击选择/双击或 Enter 执行”，并在 Task 4 前确认 |
| 当前环境无法执行 xcodebuild | High | 将 Developer Directory 切到完整 Xcode 后再开始实现；未跑绿测试不得进入发布阶段 |

## Open Questions

- History 行是否继续“单击立即执行”，还是与 Prompt 统一为“单击选择、双击/Enter 执行”？
- 标签名称是限制空格/`#`，还是支持引号语法 `#"代码 审查"`？建议支持引号语法并禁止名称内换行。
- 单条删除采用 Undo（推荐）还是确认框？
- Prompt 编辑器第一版是否只支持纯文本（推荐），暂不引入富文本/变量模板？
