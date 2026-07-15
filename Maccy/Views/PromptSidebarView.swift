import SwiftUI

struct PromptSidebarView: View {
  @Environment(AppState.self) private var appState
  @Binding var sheet: PromptEditorSheet?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Button("新建 Prompt") { sheet = .createPrompt }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("prompt-create-button")
        Button {
          appState.selectAllPrompts()
        } label: {
          sidebarRow(
            "全部 Prompt", selected: appState.isPromptCategoryFilterSelected(.all),
            count: appState.promptLibrary.items.count)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prompt-filter-all")

        Button {
          appState.selectPromptRootCategory()
        } label: {
          sidebarRow(
            "Prompt 根目录",
            selected: appState.isPromptCategoryFilterSelected(.root),
            count: appState.promptRootCategoryID.map { appState.categoryCount($0) } ?? 0
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prompt-filter-root")

        PromptSidebarHeader(title: "子书签") { sheet = .createBookmark }
        ForEach(appState.promptCategoryStore.bookmarkCategories, id: \.id) { category in
          Button {
            appState.selectPromptCategory(category.id)
          } label: {
            sidebarRow(
              category.name,
              selected: appState.isPromptCategoryFilterSelected(.category(category.id)),
              count: appState.categoryCount(category.id)
            )
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("重命名") { sheet = .renameBookmark(category) }
            Button("删除", role: .destructive) {
              do {
                try appState.deletePromptBookmark(category)
              } catch {
                appState.promptErrorMessage = error.localizedDescription
              }
            }
          }
        }

        Divider()
        PromptSidebarHeader(title: "标签") { sheet = .createTag }
        ForEach(appState.promptTagStore.tags, id: \.id) { tag in
          Button {
            appState.togglePromptTagFilter(tag.id)
          } label: {
            sidebarRow(
              "#\(tag.name)",
              selected: appState.promptFilter.selectedTagIDs.contains(tag.id),
              count: appState.tagCount(tag.id)
            )
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("重命名") { sheet = .renameTag(tag) }
            Button("删除", role: .destructive) { appState.deletePromptTag(tag) }
          }
        }
      }
      .padding(.vertical, 6)
    }
    .accessibilityIdentifier("prompt-sidebar")
  }

  private func sidebarRow(_ title: String, selected: Bool, count: Int) -> some View {
    HStack(spacing: 6) {
      Text(title).lineLimit(1)
      Spacer(minLength: 0)
      Text(String(count)).font(.caption).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .background(selected ? Color.accentColor.opacity(0.18) : .clear)
    .clipShape(.rect(cornerRadius: 6))
  }
}

private struct PromptSidebarHeader: View {
  let title: String
  let action: () -> Void
  var body: some View {
    HStack {
      Text(title).font(.headline)
      Spacer()
      Button("新建", action: action).buttonStyle(.borderless).font(.caption)
    }
  }
}

struct PromptFilterBar: View {
  @Environment(AppState.self) private var appState
  @Binding var showInspector: Bool

  var body: some View {
    HStack(spacing: 8) {
      Picker(
        "排序",
        selection: Binding(
          get: { appState.promptFilter.sortOrder },
          set: { appState.setPromptSortOrder($0) }
        )
      ) {
        Text("最近更新").tag(PromptSortOrder.recentlyUpdated)
        Text("最近使用").tag(PromptSortOrder.recentlyUsed)
        Text("使用频率").tag(PromptSortOrder.usageFrequency)
        Text("标题").tag(PromptSortOrder.title)
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .accessibilityIdentifier("prompt-sort-picker")

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          if let categoryTitle = appState.promptCategoryFilterTitle {
            FilterChip(title: categoryTitle) { appState.selectAllPrompts() }
          }
          ForEach(
            Array(appState.promptFilter.selectedTagIDs).sorted(by: { $0.uuidString < $1.uuidString }
            ),
            id: \.self
          ) { tagID in
            if let tag = appState.promptTagStore.tags.first(where: { $0.id == tagID }) {
              FilterChip(title: "#\(tag.name)") { appState.togglePromptTagFilter(tagID) }
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if hasActiveFilters {
        Button("清除全部") { appState.clearPromptFilters() }
          .buttonStyle(.borderless)
          .accessibilityIdentifier("prompt-clear-filters")
      }
      Button(
        showInspector
          ? NSLocalizedString("隐藏详情", comment: "Prompt inspector")
          : NSLocalizedString("显示详情", comment: "Prompt inspector")
      ) { showInspector.toggle() }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("prompt-toggle-inspector-bar")
    }
    .font(.caption)
  }

  private var hasActiveFilters: Bool {
    !appState.promptFilter.searchQuery.isEmpty || !appState.promptFilter.selectedTagIDs.isEmpty
      || appState.promptFilter.categoryFilter != .all
  }
}

private struct FilterChip: View {
  let title: String
  let onRemove: () -> Void
  var body: some View {
    Button(action: onRemove) {
      Label(title, systemImage: "xmark.circle.fill")
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }
}
