# iMaccy Upgrade Checklist

## Phase 0 — Baseline

- [ ] Task 1: 建立 build/test、窗口回归和性能基线（命令与诊断已完成，实测基线等待完整 Xcode）

## Phase 1 — Window & Activation Correctness

- [x] Task 2: 提取 `WindowDismissalPolicy` 并添加竞态测试
- [x] Task 3: 统一 FloatingPanel 与 scene phase 生命周期
- [x] Task 4: 统一 select/copy/paste 与 pointer/keyboard 焦点恢复

### Checkpoint A

- [ ] 外点关闭稳定，快速复焦不误关
- [ ] sheet、popover、context menu、emoji picker 行为正确
- [ ] 鼠标与键盘粘贴都进入原应用

## Phase 2 — Prompt Data Correctness

- [x] Task 5: 清理孤儿 link，验证 category/tag 引用
- [x] Task 6: 明确搜索、重复项和 usage 语义

## Phase 3 — Performance

- [x] Task 7: 建立 PromptSnapshot 索引与缓存筛选
- [x] Task 8: 批量操作改为单事务
- [x] Task 9: 优化 Throttler、History 查重/容量和 Storage.size
- [ ] Task 10: 分阶段启动与首次弹窗加载（已懒加载并显示 loading，SwiftData 主 context fetch 仍需真机基线验证）

### Checkpoint B

- [ ] Prompt 数据完整性测试通过
- [ ] 100/1,000/10,000 Prompt 性能结果已记录
- [ ] 500/5,000 History 性能结果已记录

## Phase 4 — Prompt UX & UI

- [x] Task 11: 拆分并自适应 Prompt Workspace
- [x] Task 12: 新建、编辑、复制副本和未保存保护
- [x] Task 13: 根目录筛选、filter chips、计数和排序
- [x] Task 14: Shift/⌘A 多选、三态标签、批量删除与 Undo
- [ ] Task 15: 本地化、无障碍、UI 自动化和发布回归（实现已完成，发布回归等待完整 Xcode/SwiftLint）

### Checkpoint C

- [ ] 新建→编辑→归类→搜索→复制/粘贴端到端通过
- [ ] 不同窗口宽度、键盘操作与 VoiceOver 通过
- [ ] 全量测试、SwiftLint、Debug/Release build 通过
## Verification status (2026-07-16)

- Implementation and static validation are complete.
- `swiftc -frontend -parse`, focused pure-Swift type checks, project/plist/localization validation, and `git diff --check` pass.
- Full `xcodebuild`, UI execution, SwiftLint, and Release/Distribution smoke checks remain blocked because this machine only has Command Line Tools and no complete Xcode installation.
