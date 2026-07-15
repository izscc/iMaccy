import AppKit
import Defaults
import SwiftUI

struct PromptListView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          if appState.visiblePromptItems.isEmpty {
            PromptListEmptyState()
          } else {
            ForEach(appState.visiblePromptItems, id: \.id) { item in PromptListRow(item: item) }
          }
        }
      }
      .task(id: appState.scrollTarget) {
        guard let target = appState.scrollTarget else { return }
        try? await Task.sleep(for: .milliseconds(10))
        proxy.scrollTo(target)
        appState.scrollTarget = nil
      }
    }
    .accessibilityIdentifier("prompt-list")
  }
}

private struct PromptListRow: View {
  @Environment(AppState.self) private var appState
  let item: PromptItem

  var body: some View {
    ListItemView(
      id: item.id,
      appIcon: nil,
      image: nil,
      accessoryImage: ColorImage.from(item.title),
      attributedTitle: nil,
      shortcuts: [],
      isSelected: appState.isPromptItemSelected(item),
      help: nil
    ) {
      HStack(spacing: 6) {
        Image(systemName: item.isFavorite ? "star.fill" : "star")
          .foregroundStyle(item.isFavorite ? .yellow : .secondary)
          .accessibilityLabel(Text(item.isFavorite ? localized("已收藏") : localized("未收藏")))
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title).lineLimit(1)
          Text(item.plainText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        if let category = appState.promptCategoryBadgeName(for: item) {
          PromptMetaChip(title: category)
        }
        ForEach(appState.promptTagSummary(for: item).prefix(2), id: \.id) { tag in
          PromptMetaChip(title: "#\(tag.name)")
        }
      }
    }
    .contentShape(.rect)
    .onTapGesture(count: 2) { appState.selectPromptFromPointer(item) }
    .onTapGesture {
      let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if flags.contains(.shift) {
        appState.extendPromptSelection(to: item)
      } else if flags.contains(.command) {
        appState.togglePromptMultiSelection(item)
      } else {
        appState.selectPromptListItem(item)
      }
    }
    .contextMenu {
      Button(item.isFavorite ? localized("取消收藏") : localized("收藏")) {
        appState.toggleFavoritePrompt(item)
      }
      Button("复制 Prompt") { appState.copyPrompt(item) }
      Button("粘贴并关闭") { appState.pastePrompt(item) }
      Button("编辑") { NotificationCenter.default.post(name: .promptEditRequested, object: item) }
      Button("编辑标签…") {
        NotificationCenter.default.post(name: .promptTagsEditRequested, object: item)
      }
      Button("复制副本") {
        do {
          _ = try appState.duplicatePrompt(item)
        } catch {
          appState.promptErrorMessage = error.localizedDescription
        }
      }
      Button("删除", role: .destructive) { appState.deletePrompt(item) }
    }
    .accessibilityIdentifier("prompt-row-\(item.id.uuidString)")
    .accessibilityLabel(accessibilityDescription)
    .accessibilityValue(
      appState.isPromptItemSelected(item) ? localized("已选中") : localized("未选中")
    )
    .accessibilityHint(accessibilityHint)
  }

  private var accessibilityDescription: String {
    var parts = [item.title, item.isFavorite ? localized("已收藏") : localized("未收藏")]
    parts.append(
      String(
        format: localized("子书签 %@"),
        appState.promptCategoryName(for: item)
      )
    )
    let tagNames = appState.promptTags(for: item).map(\.name)
    if !tagNames.isEmpty {
      parts.append(String(format: localized("标签 %@"), tagNames.joined(separator: ", ")))
    }
    return parts.joined(separator: localized("，"))
  }

  private var accessibilityHint: String {
    if Defaults[.pasteByDefault] {
      return localized("双击粘贴，按住 Command 多选，按住 Shift 范围选择")
    }
    return localized("双击复制，按住 Command 多选，按住 Shift 范围选择")
  }

  private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "Prompt list accessibility")
  }
}

private struct PromptListEmptyState: View {
  @Environment(AppState.self) private var appState
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if appState.isPromptLoading {
        ProgressView("正在加载 Prompt…")
      } else if appState.promptSearchHasUnterminatedQuote {
        Text("标签引号未闭合").font(.headline)
        Text("请补全引号后再搜索。").foregroundStyle(.secondary)
      } else if !appState.unknownPromptTagNames.isEmpty {
        Text(
          String(
            format: NSLocalizedString("未知标签：%@", comment: "Unknown Prompt tags"),
            appState.unknownPromptTagNames.map { "#\($0)" }.joined(separator: ", ")
          )
        )
        .font(.headline)
        Text("请检查标签名称或清除筛选条件。").foregroundStyle(.secondary)
      } else if appState.promptLibrary.items.isEmpty {
        Text("还没有 Prompt").font(.headline)
        Text("可从历史记录归档，或使用新建按钮创建。").foregroundStyle(.secondary)
      } else {
        Text("没有匹配的 Prompt").font(.headline)
        Text("尝试清除筛选条件或换一个关键词。").foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
  }
}

struct PromptBulkActionBar: View {
  @Environment(AppState.self) private var appState
  @Binding var sheet: PromptEditorSheet?
  @Binding var showDelete: Bool
  var body: some View {
    HStack(spacing: 6) {
      Text(
        String(
          format: NSLocalizedString("已选择 %lld 项", comment: "Prompt selection count"),
          Int64(appState.selectedPromptIDs.count)
        )
      )
      .foregroundStyle(.secondary)
      Button("移动到根") { appState.bulkAssignPromptsToCategory(nil) }
      Button("收藏") { appState.bulkSetFavoriteForSelectedPrompts(true) }
      Menu("更多") {
        Menu("移动到子书签") {
          ForEach(appState.promptCategoryStore.bookmarkCategories, id: \.id) { category in
            Button(category.name) { appState.bulkAssignPromptsToCategory(category.id) }
          }
        }
        Button("添加标签…") { sheet = .bulkAddTags }
        Button("移除标签…") { sheet = .bulkRemoveTags }
        Button("删除", role: .destructive) { showDelete = true }
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .accessibilityIdentifier("prompt-bulk-action-bar")
  }
}

extension Notification.Name {
  static let promptEditRequested = Notification.Name("PromptEditRequested")
  static let promptTagsEditRequested = Notification.Name("PromptTagsEditRequested")
}

struct PromptMetaChip: View {
  let title: String
  var body: some View {
    Text(title)
      .font(.caption)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.secondary.opacity(0.12))
      .clipShape(.capsule)
  }
}
