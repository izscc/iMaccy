import Defaults
import SwiftUI

struct PromptWorkspaceView: View {
  @FocusState.Binding var searchFocused: Bool

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  @State private var editorSheet: PromptEditorSheet?
  @State private var deleteTarget: PromptDeleteTarget?
  @State private var errorMessage: String?
  @State private var showBulkDeleteConfirmation = false

  private var sidebarWidth: CGFloat { 220 }
  private var detailWidth: CGFloat { 300 }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      PromptSidebarView(
        selectedCategoryID: appState.promptFilter.selectedCategoryID,
        selectedTagIDs: appState.promptFilter.selectedTagIDs,
        bookmarks: appState.promptCategoryStore.bookmarkCategories,
        tags: appState.promptTagStore.tags,
        onSelectAll: { appState.setPromptCategoryFilter(nil) },
        onSelectBookmark: { appState.setPromptCategoryFilter($0.id) },
        onToggleTag: { appState.togglePromptTagFilter($0.id) },
        onCreateBookmark: { editorSheet = .createBookmark },
        onRenameBookmark: { editorSheet = .renameBookmark($0) },
        onDeleteBookmark: { deleteTarget = .bookmark($0) },
        onCreateTag: { editorSheet = .createTag },
        onRenameTag: { editorSheet = .renameTag($0) },
        onDeleteTag: { deleteTarget = .tag($0) }
      )
      .frame(width: sidebarWidth, alignment: .topLeading)

      Divider()

      VStack(alignment: .leading, spacing: 10) {
        if appState.isPromptMultiSelecting {
          PromptBulkActionBar(
            selectionCount: appState.selectedPromptIDs.count,
            bookmarks: appState.promptCategoryStore.bookmarkCategories,
            recentBookmarks: appState.recentPromptBookmarks,
            onMoveToRecent: { appState.bulkAssignPromptsToCategory($0.id) },
            onMoveToBookmark: { appState.bulkAssignPromptsToCategory($0.id) },
            onMoveToRoot: { appState.bulkAssignPromptsToCategory(nil) },
            onAddTags: { editorSheet = .bulkAddTags },
            onRemoveTags: { editorSheet = .bulkRemoveTags },
            onFavorite: { appState.bulkSetFavoriteForSelectedPrompts(true) },
            onUnfavorite: { appState.bulkSetFavoriteForSelectedPrompts(false) },
            onDelete: { showBulkDeleteConfirmation = true }
          )
        }

        PromptListView(
          items: appState.visiblePromptItems,
          emptyState: emptyState,
          bookmarks: appState.promptCategoryStore.bookmarkCategories,
          recentBookmarks: appState.recentPromptBookmarks,
        tagsForItem: { appState.promptTagSummary(for: $0) },
          badgeNameForItem: { appState.promptCategoryBadgeName(for: $0) },
          onSelect: { appState.selectPromptListItem($0) },
          onToggleMultiSelection: { appState.togglePromptMultiSelection($0) },
          onActivate: { appState.selectPromptFromPointer($0) },
          onToggleFavorite: { appState.toggleFavoritePrompt($0) },
          onMoveToRecentBookmark: { item, category in appState.assignPromptToCategory(item, categoryID: category.id) },
          onMoveToRoot: { appState.assignPromptToCategory($0, categoryID: nil) },
          onMoveToBookmark: { item, category in appState.assignPromptToCategory(item, categoryID: category.id) },
          onEditTags: { editorSheet = .editTags($0) },
          onDelete: { appState.deletePrompt($0) }
        )
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)

      Divider()

      PromptDetailView(
        item: appState.selectedPromptItem,
        bookmarks: appState.promptCategoryStore.bookmarkCategories,
        recentBookmarks: appState.recentPromptBookmarks,
        currentCategoryName: appState.selectedPromptItem.map { appState.promptCategoryName(for: $0) } ?? "Prompt 根目录",
        promptTags: appState.selectedPromptItem.map { appState.promptTags(for: $0) } ?? [],
        onToggleFavorite: { appState.toggleFavoritePrompt($0) },
        onQuickAssign: { item, category in appState.assignPromptToCategory(item, categoryID: category.id) },
        onSelectCategory: { item, categoryID in appState.assignPromptToCategory(item, categoryID: categoryID) },
        onRemoveTag: { item, tag in appState.removePromptTag(tag, from: item) },
        onEditTags: { if let item = $0 { editorSheet = .editTags(item) } },
        onCopy: { appState.selectPrompt($0) }
      )
      .frame(width: detailWidth, alignment: .topLeading)
    }
    .padding(.horizontal, 10)
    .background {
      GeometryReader { geo in
        Color.clear
          .task {
            appState.popup.pinnedItemsHeight = 0
          }
          .task(id: appState.popup.needsResize) {
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }

            if appState.popup.needsResize {
              appState.popup.resize(height: geo.size.height)
            }
          }
      }
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        searchFocused = true
        appState.isKeyboardNavigating = true
        if appState.selectedPromptItem == nil {
          appState.selectPromptListItem(appState.visiblePromptItems.first)
        }
      } else {
        appState.isKeyboardNavigating = true
      }
    }
    .sheet(item: $editorSheet) { sheet in
      switch sheet {
      case .createBookmark:
        PromptNameEditorSheet(
          title: "新建子书签",
          placeholder: "输入子书签名称",
          confirmTitle: "创建"
        ) { name in
          try appState.createPromptBookmark(name: name)
        }
      case .renameBookmark(let category):
        PromptNameEditorSheet(
          title: "重命名子书签",
          placeholder: "输入子书签名称",
          initialName: category.name,
          confirmTitle: "保存"
        ) { name in
          try appState.renamePromptBookmark(category, name: name)
        }
      case .createTag:
        PromptNameEditorSheet(
          title: "新建标签",
          placeholder: "输入标签名称",
          confirmTitle: "创建"
        ) { name in
          try appState.createPromptTag(name: name)
        }
      case .renameTag(let tag):
        PromptNameEditorSheet(
          title: "重命名标签",
          placeholder: "输入标签名称",
          initialName: tag.name,
          confirmTitle: "保存"
        ) { name in
          try appState.renamePromptTag(tag, name: name)
        }
      case .editTags(let item):
        PromptTagAssignmentSheet(promptItem: item)
      case .bulkAddTags:
        PromptBulkTagSheet(mode: .add)
      case .bulkRemoveTags:
        PromptBulkTagSheet(mode: .remove)
      }
    }
    .alert(item: $deleteTarget) { target in
      switch target {
      case .bookmark(let category):
        return Alert(
          title: Text("删除子书签"),
          message: Text("删除后，该子书签下的 Prompt 会移回 Prompt 根目录。"),
          primaryButton: .destructive(Text("删除")) {
            do {
              try appState.deletePromptBookmark(category)
            } catch {
              errorMessage = error.localizedDescription
            }
          },
          secondaryButton: .cancel(Text("取消"))
        )
      case .tag(let tag):
        return Alert(
          title: Text("删除标签"),
          message: Text("删除后，该标签会从所有 Prompt 中移除。"),
          primaryButton: .destructive(Text("删除")) {
            appState.deletePromptTag(tag)
          },
          secondaryButton: .cancel(Text("取消"))
        )
      }
    }
    .modifier(PromptBulkDeleteAlert(
      isPresented: $showBulkDeleteConfirmation,
      selectionCount: appState.selectedPromptIDs.count,
      onDelete: { appState.bulkDeleteSelectedPrompts() }
    ))
    .alert("操作失败", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("确定", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private var emptyState: PromptEmptyState {
    let items = appState.promptLibrary.items
    let selectedCategory = appState.promptFilter.selectedCategoryID
    let selectedTags = appState.promptFilter.selectedTagIDs
    let search = appState.promptFilter.searchQuery.promptTrimmedName

    if items.isEmpty {
      return .init(
        title: "还没有 Prompt",
        message: "在历史列表中右键任意文本内容，选择“移动到 Prompt…”或指定子书签，就可以把它沉淀到这里。"
      )
    }

    if !search.isEmpty, search.contains("#") {
      return .init(title: "当前搜索条件下暂无 Prompt", message: "你可以减少 #标签 条件，或清空搜索后再试。")
    }

    if !search.isEmpty {
      return .init(title: "没有找到匹配的 Prompt", message: "试试更短的关键词，或清空当前筛选条件。")
    }

    if !selectedTags.isEmpty, selectedCategory != nil {
      return .init(title: "这个子书签和标签组合下暂无 Prompt", message: "你可以切换标签、切换子书签，或新建一个 Prompt。")
    }

    if !selectedTags.isEmpty {
      return .init(title: "当前标签组合下暂无 Prompt", message: "多选标签使用交集筛选，可以减少选中的标签试试。")
    }

    if selectedCategory != nil {
      return .init(title: "当前子书签下暂无 Prompt", message: "可以把已有 Prompt 移到这个子书签，或直接从历史归档到这里。")
    }

    if appState.promptFilter.favoritesOnly {
      return .init(title: "还没有收藏的 Prompt", message: "把常用 Prompt 标记为“收藏”后，这里会显示它们。")
    }

    return .init(title: "暂无 Prompt", message: "你可以从历史中归档文本内容，开始整理 Prompt。")
  }
}

private struct PromptSidebarView: View {
  let selectedCategoryID: UUID?
  let selectedTagIDs: Set<UUID>
  let bookmarks: [PromptCategory]
  let tags: [PromptTag]
  let onSelectAll: () -> Void
  let onSelectBookmark: (PromptCategory) -> Void
  let onToggleTag: (PromptTag) -> Void
  let onCreateBookmark: () -> Void
  let onRenameBookmark: (PromptCategory) -> Void
  let onDeleteBookmark: (PromptCategory) -> Void
  let onCreateTag: () -> Void
  let onRenameTag: (PromptTag) -> Void
  let onDeleteTag: (PromptTag) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        PromptSidebarSectionHeader(title: "子书签", actionTitle: "新建") {
          onCreateBookmark()
        }

        PromptSidebarRow(title: "全部 Prompt", selected: selectedCategoryID == nil) {
          onSelectAll()
        }

        if bookmarks.isEmpty {
          Text("暂无子书签")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
        } else {
          ForEach(bookmarks, id: \.id) { bookmark in
            PromptSidebarRow(title: bookmark.name, selected: selectedCategoryID == bookmark.id) {
              onSelectBookmark(bookmark)
            }
            .contextMenu {
              Button("重命名") {
                onRenameBookmark(bookmark)
              }
              Button("删除", role: .destructive) {
                onDeleteBookmark(bookmark)
              }
            }
          }
        }

        Divider()
          .padding(.vertical, 2)

        PromptSidebarSectionHeader(title: "标签", actionTitle: "新建") {
          onCreateTag()
        }

        if tags.isEmpty {
          Text("暂无标签")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
        } else {
          ForEach(tags, id: \.id) { tag in
            PromptSidebarRow(title: "#\(tag.name)", selected: selectedTagIDs.contains(tag.id)) {
              onToggleTag(tag)
            }
            .contextMenu {
              Button("重命名") {
                onRenameTag(tag)
              }
              Button("删除", role: .destructive) {
                onDeleteTag(tag)
              }
            }
          }
        }
      }
      .padding(.vertical, 4)
    }
  }
}

private struct PromptSidebarSectionHeader: View {
  let title: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.headline)
      Spacer(minLength: 0)
      Button(actionTitle, action: action)
        .buttonStyle(.borderless)
        .font(.caption)
    }
  }
}

private struct PromptSidebarRow: View {
  let title: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
      .clipShape(.rect(cornerRadius: 6))
    }
    .buttonStyle(.plain)
  }
}

private struct PromptBulkActionBar: View {
  let selectionCount: Int
  let bookmarks: [PromptCategory]
  let recentBookmarks: [PromptCategory]
  let onMoveToRecent: (PromptCategory) -> Void
  let onMoveToBookmark: (PromptCategory) -> Void
  let onMoveToRoot: () -> Void
  let onAddTags: () -> Void
  let onRemoveTags: () -> Void
  let onFavorite: () -> Void
  let onUnfavorite: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text("已选择 \(selectionCount) 项")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if !recentBookmarks.isEmpty {
        Menu("移到最近子书签") {
          ForEach(recentBookmarks, id: \.id) { bookmark in
            Button(bookmark.name) {
              onMoveToRecent(bookmark)
            }
          }
        }
      }

      Menu("移动到子书签") {
        if bookmarks.isEmpty {
          Button("暂无子书签") {}
            .disabled(true)
        } else {
          ForEach(bookmarks, id: \.id) { bookmark in
            Button(bookmark.name) {
              onMoveToBookmark(bookmark)
            }
          }
        }
      }

      Button("移回根目录") {
        onMoveToRoot()
      }
      Button("添加标签…") {
        onAddTags()
      }
      Button("移除标签…") {
        onRemoveTags()
      }
      Button("收藏") {
        onFavorite()
      }
      Button("取消收藏") {
        onUnfavorite()
      }
      Button("删除", role: .destructive) {
        onDelete()
      }
    }
    .buttonStyle(.bordered)
    .font(.caption)
  }
}

private struct PromptBulkDeleteAlert: ViewModifier {
  @Binding var isPresented: Bool
  let selectionCount: Int
  let onDelete: () -> Void

  @Default(.confirmPromptBulkDelete) private var confirmPromptBulkDelete

  func body(content: Content) -> some View {
    content
      .onChange(of: isPresented) {
        guard isPresented, !confirmPromptBulkDelete else { return }
        isPresented = false
        onDelete()
      }
      .alert("批量删除 Prompt", isPresented: $isPresented) {
        Button("取消", role: .cancel) {}
        Button("删除", role: .destructive) {
          onDelete()
        }
      } message: {
        Text("确定要删除已选中的 \(selectionCount) 个 Prompt 吗？此操作无法撤销。")
      }
  }
}

private struct PromptListView: View {
  let items: [PromptItem]
  let emptyState: PromptEmptyState
  let bookmarks: [PromptCategory]
  let recentBookmarks: [PromptCategory]
  let tagsForItem: (PromptItem) -> [PromptTag]
  let badgeNameForItem: (PromptItem) -> String?
  let onSelect: (PromptItem) -> Void
  let onToggleMultiSelection: (PromptItem) -> Void
  let onActivate: (PromptItem) -> Void
  let onToggleFavorite: (PromptItem) -> Void
  let onMoveToRecentBookmark: (PromptItem, PromptCategory) -> Void
  let onMoveToRoot: (PromptItem) -> Void
  let onMoveToBookmark: (PromptItem, PromptCategory) -> Void
  let onEditTags: (PromptItem) -> Void
  let onDelete: (PromptItem) -> Void

  @Environment(AppState.self) private var appState

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if items.isEmpty {
            PromptEmptyStateView(state: emptyState)
          } else {
            ForEach(items, id: \.id) { item in
              PromptRowView(
                item: item,
                tags: tagsForItem(item),
                categoryBadge: badgeNameForItem(item),
                bookmarks: bookmarks,
                recentBookmarks: recentBookmarks,
                onSelect: { onSelect(item) },
                onToggleMultiSelection: { onToggleMultiSelection(item) },
                onActivate: { onActivate(item) },
                onToggleFavorite: { onToggleFavorite(item) },
                onMoveToRecentBookmark: { onMoveToRecentBookmark(item, $0) },
                onMoveToRoot: { onMoveToRoot(item) },
                onMoveToBookmark: { onMoveToBookmark(item, $0) },
                onEditTags: { onEditTags(item) },
                onDelete: { onDelete(item) }
              )
            }
          }
        }
        .task(id: appState.scrollTarget) {
          guard appState.scrollTarget != nil else { return }

          try? await Task.sleep(for: .milliseconds(10))
          guard !Task.isCancelled else { return }

          if let selection = appState.scrollTarget {
            proxy.scrollTo(selection)
            appState.scrollTarget = nil
          }
        }
      }
      .contentMargins(.leading, 10, for: .scrollIndicators)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct PromptRowView: View {
  let item: PromptItem
  let tags: [PromptTag]
  let categoryBadge: String?
  let bookmarks: [PromptCategory]
  let recentBookmarks: [PromptCategory]
  let onSelect: () -> Void
  let onToggleMultiSelection: () -> Void
  let onActivate: () -> Void
  let onToggleFavorite: () -> Void
  let onMoveToRecentBookmark: (PromptCategory) -> Void
  let onMoveToRoot: () -> Void
  let onMoveToBookmark: (PromptCategory) -> Void
  let onEditTags: () -> Void
  let onDelete: () -> Void

  @Environment(AppState.self) private var appState

  private var displayedTags: [PromptTag] { Array(tags.prefix(2)) }
  private var remainingTagCount: Int { max(tags.count - displayedTags.count, 0) }

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
        Text(verbatim: item.isFavorite ? "★ \(item.title)" : item.title)

        if let categoryBadge {
          PromptMetaChip(title: categoryBadge)
        }

        ForEach(displayedTags, id: \.id) { tag in
          PromptMetaChip(title: "#\(tag.name)")
        }

        if remainingTagCount > 0 {
          Text("+\(remainingTagCount)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .contentShape(.rect)
    .gesture(
      TapGesture(count: 2)
        .exclusively(before: TapGesture())
        .onEnded { value in
          switch value {
          case .first:
            onActivate()
          case .second:
            let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command) {
              onToggleMultiSelection()
            } else {
              onSelect()
            }
          }
        }
    )
    .contextMenu {
      Button(item.isFavorite ? "取消收藏" : "收藏") {
        onToggleFavorite()
      }

      if !recentBookmarks.isEmpty {
        Menu("移动到最近子书签") {
          ForEach(recentBookmarks, id: \.id) { bookmark in
            Button(bookmark.name) {
              onMoveToRecentBookmark(bookmark)
            }
          }
        }
      }

      Menu("移动到子书签") {
        if bookmarks.isEmpty {
          Button("暂无子书签") {}
            .disabled(true)
        } else {
          ForEach(bookmarks, id: \.id) { bookmark in
            Button(bookmark.name) {
              onMoveToBookmark(bookmark)
            }
          }
        }
      }

      Button("移回 Prompt 根目录") {
        onMoveToRoot()
      }

      Button("添加标签…") {
        onEditTags()
      }

      Button("从 Prompt 删除", role: .destructive) {
        onDelete()
      }
    }
  }
}

private struct PromptDetailView: View {
  let item: PromptItem?
  let bookmarks: [PromptCategory]
  let recentBookmarks: [PromptCategory]
  let currentCategoryName: String
  let promptTags: [PromptTag]
  let onToggleFavorite: (PromptItem?) -> Void
  let onQuickAssign: (PromptItem?, PromptCategory) -> Void
  let onSelectCategory: (PromptItem?, UUID?) -> Void
  let onRemoveTag: (PromptItem, PromptTag) -> Void
  let onEditTags: (PromptItem?) -> Void
  let onCopy: (PromptItem?) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let item {
        Text(item.title)
          .font(.headline)
          .textSelection(.enabled)

        ScrollView {
          Text(item.plainText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity, alignment: .top)

        Divider()

        Toggle("收藏", isOn: Binding(
          get: { item.isFavorite },
          set: { _ in onToggleFavorite(item) }
        ))
        .toggleStyle(.switch)

        if !recentBookmarks.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("快捷归类")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            HStack(spacing: 6) {
              ForEach(recentBookmarks, id: \.id) { bookmark in
                Button(bookmark.name) {
                  onQuickAssign(item, bookmark)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("子书签")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Picker("子书签", selection: Binding<UUID?>(
            get: { bookmarks.first(where: { $0.id == item.categoryID })?.id },
            set: { onSelectCategory(item, $0) }
          )) {
            Text("Prompt 根目录").tag(Optional<UUID>.none)
            ForEach(bookmarks, id: \.id) { bookmark in
              Text(bookmark.name).tag(Optional(bookmark.id))
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("标签")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("添加标签") {
              onEditTags(item)
            }
            .buttonStyle(.borderless)
          }

          if promptTags.isEmpty {
            Text("暂无标签")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
              ForEach(promptTags, id: \.id) { tag in
                PromptRemovableTagChip(title: tag.name) {
                  onRemoveTag(item, tag)
                }
              }
            }
          }
        }

        Divider()

        detailRow(title: "当前归属", value: currentCategoryName)
        detailRow(title: "来源历史", value: item.sourceHistoryItemID == nil ? "无" : "有")
        detailRow(title: "使用次数", value: String(item.usageCount))

        HStack(spacing: 8) {
          Button(item.isFavorite ? "取消收藏" : "收藏") {
            onToggleFavorite(item)
          }

          Button("复制 Prompt") {
            onCopy(item)
          }
        }
        .buttonStyle(.bordered)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("Prompt 详情")
            .font(.headline)
          Text("选择一个 Prompt 后，可以在这里查看全文、切换子书签、编辑标签和收藏状态。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func detailRow(title: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Text(value)
        .multilineTextAlignment(.trailing)
    }
    .font(.subheadline)
  }
}

private struct PromptNameEditorSheet: View {
  let title: String
  let placeholder: String
  var initialName: String = ""
  let confirmTitle: String
  let onSubmit: (String) throws -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var errorMessage: String?

  init(
    title: String,
    placeholder: String,
    initialName: String = "",
    confirmTitle: String,
    onSubmit: @escaping (String) throws -> Void
  ) {
    self.title = title
    self.placeholder = placeholder
    self.initialName = initialName
    self.confirmTitle = confirmTitle
    self.onSubmit = onSubmit
    _name = State(initialValue: initialName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)

      TextField(placeholder, text: $name)
        .textFieldStyle(.roundedBorder)

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer(minLength: 0)
        Button("取消") {
          dismiss()
        }
        Button(confirmTitle) {
          do {
            try onSubmit(name)
            dismiss()
          } catch {
            errorMessage = error.localizedDescription
          }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 340)
  }
}

private enum PromptBulkTagMode {
  case add
  case remove

  var title: String {
    switch self {
    case .add:
      return "批量添加标签"
    case .remove:
      return "批量移除标签"
    }
  }
}

private struct PromptBulkTagSheet: View {
  let mode: PromptBulkTagMode

  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  @State private var selectedTagIDs: Set<UUID> = []
  @State private var newTagName: String = ""
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(mode.title)
        .font(.headline)

      Text("已选中 \(appState.selectedPromptIDs.count) 个 Prompt")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if mode == .add {
        TextField("输入新标签名称（可选）", text: $newTagName)
          .textFieldStyle(.roundedBorder)
      }

      if appState.promptTagStore.tags.isEmpty {
        Text(mode == .add ? "还没有标签，输入上方名称即可直接创建。" : "当前没有可移除的标签。")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(availableTags, id: \.id) { tag in
              Toggle(isOn: Binding(
                get: { selectedTagIDs.contains(tag.id) },
                set: { isOn in
                  if isOn {
                    selectedTagIDs.insert(tag.id)
                  } else {
                    selectedTagIDs.remove(tag.id)
                  }
                }
              )) {
                Text(tag.name)
              }
              .toggleStyle(.checkbox)
            }
          }
        }
        .frame(maxHeight: 180)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer(minLength: 0)
        Button("取消") {
          dismiss()
        }
        Button("保存") {
          do {
            switch mode {
            case .add:
              var finalTagIDs = selectedTagIDs
              if !newTagName.promptTrimmedName.isEmpty {
                let tag = try appState.findOrCreatePromptTag(name: newTagName)
                finalTagIDs.insert(tag.id)
              }
              appState.bulkAddPromptTagIDs(finalTagIDs)
            case .remove:
              appState.bulkRemovePromptTagIDs(selectedTagIDs)
            }
            dismiss()
          } catch {
            errorMessage = error.localizedDescription
          }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 360)
  }

  private var availableTags: [PromptTag] {
    switch mode {
    case .add:
      return appState.promptTagStore.tags
    case .remove:
      let ids = Set(appState.selectedPromptItems.flatMap { appState.promptTags(for: $0).map(\.id) })
      return appState.promptTagStore.tags.filter { ids.contains($0.id) }
    }
  }
}

private struct PromptTagAssignmentSheet: View {
  let promptItem: PromptItem

  @Environment(AppState.self) private var appState
  @Environment(\.dismiss) private var dismiss

  @State private var selectedTagIDs: Set<UUID>
  @State private var newTagName: String = ""
  @State private var errorMessage: String?

  init(promptItem: PromptItem) {
    self.promptItem = promptItem
    _selectedTagIDs = State(initialValue: [])
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("编辑标签")
        .font(.headline)

      Text(promptItem.title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      TextField("输入新标签名称（可选）", text: $newTagName)
        .textFieldStyle(.roundedBorder)

      if appState.promptTagStore.tags.isEmpty {
        Text("还没有标签，输入上方名称即可直接创建。")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(appState.promptTagStore.tags, id: \.id) { tag in
              Toggle(isOn: Binding(
                get: { selectedTagIDs.contains(tag.id) },
                set: { isOn in
                  if isOn {
                    selectedTagIDs.insert(tag.id)
                  } else {
                    selectedTagIDs.remove(tag.id)
                  }
                }
              )) {
                Text(tag.name)
              }
              .toggleStyle(.checkbox)
            }
          }
        }
        .frame(maxHeight: 180)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Spacer(minLength: 0)
        Button("取消") {
          dismiss()
        }
        Button("保存") {
          do {
            var finalTagIDs = selectedTagIDs
            if !newTagName.promptTrimmedName.isEmpty {
              let tag = try appState.findOrCreatePromptTag(name: newTagName)
              finalTagIDs.insert(tag.id)
            }
            appState.setPromptTagIDs(promptItem, tagIDs: finalTagIDs)
            dismiss()
          } catch {
            errorMessage = error.localizedDescription
          }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 360)
    .task {
      selectedTagIDs = Set(appState.promptTags(for: promptItem).map(\.id))
    }
  }
}

private struct PromptMetaChip: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.caption)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.secondary.opacity(0.12))
      .clipShape(.capsule)
  }
}

private struct PromptRemovableTagChip: View {
  let title: String
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      Text("#\(title)")
        .font(.caption)
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.caption)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.secondary.opacity(0.12))
    .clipShape(.capsule)
  }
}

private struct PromptEmptyState {
  let title: String
  let message: String
}

private struct PromptEmptyStateView: View {
  let state: PromptEmptyState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(state.title)
        .font(.headline)
      Text(state.message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 18)
    .padding(.horizontal, 10)
  }
}

private enum PromptEditorSheet: Identifiable {
  case createBookmark
  case renameBookmark(PromptCategory)
  case createTag
  case renameTag(PromptTag)
  case editTags(PromptItem)
  case bulkAddTags
  case bulkRemoveTags

  var id: String {
    switch self {
    case .createBookmark:
      return "createBookmark"
    case .renameBookmark(let category):
      return "renameBookmark-\(category.id.uuidString)"
    case .createTag:
      return "createTag"
    case .renameTag(let tag):
      return "renameTag-\(tag.id.uuidString)"
    case .editTags(let item):
      return "editTags-\(item.id.uuidString)"
    case .bulkAddTags:
      return "bulkAddTags"
    case .bulkRemoveTags:
      return "bulkRemoveTags"
    }
  }
}

private enum PromptDeleteTarget: Identifiable {
  case bookmark(PromptCategory)
  case tag(PromptTag)

  var id: String {
    switch self {
    case .bookmark(let category):
      return "bookmark-\(category.id.uuidString)"
    case .tag(let tag):
      return "tag-\(tag.id.uuidString)"
    }
  }
}
